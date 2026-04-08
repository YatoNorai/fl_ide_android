import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../models/ssh_config.dart';

/// Represents a file or directory entry returned by SFTP listing.
class SshFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;
  final DateTime modified;

  const SshFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.size,
    required this.modified,
  });
}

enum SshStatus { disconnected, connecting, connected, error }

class SshProvider extends ChangeNotifier {
  SshStatus _status = SshStatus.disconnected;
  SSHClient? _client;
  String? _error;
  SshConfig? _config;

  // Remote system info
  String? _connectedSystemInfo;
  List<String> _detectedSdks = [];
  bool _remoteIsWindows = false;
  bool _autoConnectDone = false;
  bool _isDetectingSdks = false;

  // ── SFTP session pool ──────────────────────────────────────────────────────
  // Single SFTP client reused across all operations — avoids opening a new
  // SSH channel per read/write/list call which exhausts server channel limits.
  SftpClient? _sftpClient;

  // ── Keepalive ──────────────────────────────────────────────────────────────
  Timer? _keepAliveTimer;

  // ── Getters ────────────────────────────────────────────────────────────────
  SshStatus get status => _status;
  String? get error => _error;
  SshConfig? get config => _config;
  bool get isConnected => _status == SshStatus.connected;
  String? get connectedSystemInfo => _connectedSystemInfo;
  List<String> get detectedSdks => List.unmodifiable(_detectedSdks);
  bool get remoteIsWindows => _remoteIsWindows;
  bool get isDetectingSdks => _isDetectingSdks;

  // ── Connect ────────────────────────────────────────────────────────────────

  /// Connect to the remote host using the provided [config].
  Future<void> connect(SshConfig config) async {
    _status = SshStatus.connecting;
    _error = null;
    _config = config;
    notifyListeners();

    try {
      final socket = await SSHSocket.connect(config.host, config.port);
      _client = SSHClient(
        socket,
        username: config.username,
        onPasswordRequest: config.useKeyAuth
            ? null
            : () => config.password ?? '',
        identities: config.useKeyAuth && config.privateKeyPath != null
            ? _loadIdentities(config.privateKeyPath!)
            : null,
      );
      // Wait for authentication handshake to complete
      await _client!.authenticated;
      _status = SshStatus.connected;
      notifyListeners();

      _startKeepalive();
      _watchForDisconnect();

      await _detectRemoteSystem();
      _isDetectingSdks = true;
      notifyListeners();
      _detectRemoteSdks(); // run in background, ignore future
    } catch (e) {
      _status = SshStatus.error;
      _error = e.toString();
      _client = null;
      notifyListeners();
    }
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  /// Disconnect from the remote host (user-initiated — no auto-reconnect).
  void disconnect() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _closeSftp();
    _client?.close();
    _client = null;
    _autoConnectDone = false;
    _status = SshStatus.disconnected;
    _error = null;
    _connectedSystemInfo = null;
    _detectedSdks = [];
    _remoteIsWindows = false;
    _isDetectingSdks = false;
    notifyListeners();
  }

  // ── Auto-connect ───────────────────────────────────────────────────────────

  /// Called by app when settings are loaded — auto-connects if enabled.
  void onSettingsReady({
    required bool enabled,
    required String host,
    required int port,
    required String username,
    required String password,
    required String keyPath,
    required bool useKey,
    required String remoteProjectsPath,
  }) {
    if (_autoConnectDone || !enabled || host.isEmpty || username.isEmpty) return;
    _autoConnectDone = true;
    final config = SshConfig(
      host: host,
      port: port,
      username: username,
      password: password,
      privateKeyPath: keyPath.isEmpty ? null : keyPath,
      useKeyAuth: useKey,
      remoteProjectsPath: remoteProjectsPath,
      enabled: true,
    );
    connect(config).ignore();
  }

  // ── Keepalive ──────────────────────────────────────────────────────────────

  void _startKeepalive() {
    _keepAliveTimer?.cancel();
    // Send a no-op command every 25 seconds to keep the TCP connection alive
    // through NAT routers that time out idle connections.
    _keepAliveTimer = Timer.periodic(const Duration(seconds: 25), (_) async {
      if (_status != SshStatus.connected || _client == null) return;
      try {
        await execute(':').timeout(const Duration(seconds: 5));
      } catch (_) {
        // If the keepalive fails the disconnect watcher will handle it.
      }
    });
  }

  // ── Disconnect detection + auto-reconnect ──────────────────────────────────

  void _watchForDisconnect() {
    _client?.done.then((_) {
      if (_status == SshStatus.connected) {
        _handleUnexpectedDisconnect();
      }
    });
  }

  void _handleUnexpectedDisconnect() {
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _closeSftp();
    _client = null;
    _status = SshStatus.disconnected;
    _error = 'Connection lost — reconnecting…';
    _isDetectingSdks = false;
    notifyListeners();

    // Auto-reconnect after a short delay (only if we have config).
    if (_config != null) {
      Future.delayed(const Duration(seconds: 3), () {
        if (_status != SshStatus.connected &&
            _status != SshStatus.connecting &&
            _config != null) {
          connect(_config!).ignore();
        }
      });
    }
  }

  // ── SFTP pool helpers ──────────────────────────────────────────────────────

  void _closeSftp() {
    try { _sftpClient?.close(); } catch (_) {}
    _sftpClient = null;
  }

  /// Run [fn] with a pooled SFTP client.
  /// On the first call (or after a session failure) a new SFTP session is
  /// opened; subsequent calls reuse the existing one.
  /// If the session fails mid-call we close it and retry once.
  Future<T> _withSftp<T>(Future<T> Function(SftpClient) fn) async {
    _requireConnected();
    for (int attempt = 0; attempt < 2; attempt++) {
      _sftpClient ??= await _client!.sftp();
      try {
        return await fn(_sftpClient!);
      } catch (e) {
        if (attempt == 0) {
          // Session may be stale — close and let the next iteration recreate.
          _closeSftp();
          continue;
        }
        rethrow;
      }
    }
    throw StateError('SFTP unavailable after retry');
  }

  // ── Remote system detection ────────────────────────────────────────────────

  Future<void> _detectRemoteSystem() async {
    try {
      String winCheck = '';
      try {
        winCheck = await execute('cmd /c ver').timeout(const Duration(seconds: 3));
      } catch (_) {}
      // Fallback: try 'ver' directly (some Windows SSH servers don't wrap in cmd)
      if (!winCheck.toLowerCase().contains('windows')) {
        try {
          winCheck = await execute('ver').timeout(const Duration(seconds: 3));
        } catch (_) {}
      }
      _remoteIsWindows = winCheck.toLowerCase().contains('windows');

      if (_remoteIsWindows) {
        final hostname = (await execute('cmd /c hostname').timeout(const Duration(seconds: 3))).trim();
        final ver = winCheck.trim().split('\n').first.trim();
        _connectedSystemInfo = '$hostname • $ver';
      } else {
        final hostname = (await execute('hostname').timeout(const Duration(seconds: 3))).trim();
        final os = (await execute('uname -s -r').timeout(const Duration(seconds: 3))).trim();
        _connectedSystemInfo = '$hostname • $os';
      }
      notifyListeners();
    } catch (e) {
      _connectedSystemInfo = _config?.host;
      notifyListeners();
    }
  }

  Future<void> _detectRemoteSdks() async {
    final sdks = <String>[];
    try {
      if (_remoteIsWindows) {
        // Use where.exe to find executables in PATH — simpler and more reliable
        // than PowerShell over SSH exec. where.exe writes the full path to stdout
        // when found; stdout is empty when not found (error goes to stderr).
        Future<bool> whereCheck(List<String> exeNames) async {
          for (final exe in exeNames) {
            try {
              final r = (await execute('where.exe $exe')
                  .timeout(const Duration(seconds: 4))).trim();
              if (r.isNotEmpty) return true;
            } catch (_) {}
          }
          return false;
        }

        // Check if an env var is set using cmd 'set VAR'.
        // cmd prints 'VAR=value' to stdout when set; error goes to stderr only.
        Future<bool> envVarSet(String varName) async {
          try {
            final r = (await execute('cmd /c set $varName')
                .timeout(const Duration(seconds: 3))).trim();
            return r.contains('=');
          } catch (_) {
            return false;
          }
        }

        final toolChecks = <String, Future<bool> Function()>{
          'Flutter':     () => whereCheck(['flutter']),
          'Dart':        () => whereCheck(['dart']),
          'Android SDK': () async =>
              await whereCheck(['adb']) ||
              await envVarSet('ANDROID_HOME') ||
              await envVarSet('ANDROID_SDK_ROOT'),
          'Java':        () => whereCheck(['java', 'javac']),
          'Node.js':     () => whereCheck(['node', 'npm']),
          'Python':      () => whereCheck(['python', 'python3', 'py']),
          'Git':         () => whereCheck(['git']),
        };
        for (final entry in toolChecks.entries) {
          if (await entry.value()) sdks.add(entry.key);
        }
      } else {
        final checks = <String, String>{
          'Flutter': 'which flutter 2>/dev/null || test -f ~/flutter/bin/flutter && echo ~/flutter/bin/flutter',
          'Dart': 'which dart 2>/dev/null',
          'Node.js': 'which node 2>/dev/null',
          'Python': 'which python3 2>/dev/null',
          'Java': 'which java 2>/dev/null',
          'Git': 'which git 2>/dev/null',
          'Android SDK': 'test -d "\${ANDROID_HOME:-\$HOME/Android/Sdk}" && echo yes',
        };
        for (final entry in checks.entries) {
          try {
            final r = (await execute(entry.value).timeout(const Duration(seconds: 3))).trim();
            if (r.isNotEmpty) sdks.add(entry.key);
          } catch (_) {}
        }
      }
    } catch (_) {}
    _detectedSdks = sdks;
    _isDetectingSdks = false;
    notifyListeners();
  }

  // ── SFTP file operations ───────────────────────────────────────────────────

  /// Read a remote file via SFTP and return its content as a [String].
  Future<String> readFile(String remotePath) => _withSftp((sftp) async {
    final file = await sftp.open(remotePath, mode: SftpFileOpenMode.read);
    try {
      final chunks = <Uint8List>[];
      await for (final chunk in file.read()) {
        chunks.add(chunk);
      }
      final bytes = chunks.fold<List<int>>([], (acc, c) => acc..addAll(c));
      return utf8.decode(bytes, allowMalformed: true);
    } finally {
      await file.close();
    }
  });

  /// Write [content] to a remote file via SFTP.
  Future<void> writeFile(String remotePath, String content) => _withSftp((sftp) async {
    final file = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(Uint8List.fromList(utf8.encode(content)));
    } finally {
      await file.close();
    }
  });

  /// List the contents of a remote directory via SFTP.
  Future<List<SshFileEntry>> listDirectory(String remotePath) => _withSftp((sftp) async {
    final items = await sftp.listdir(remotePath);
    return items
        .where((e) => e.filename != '.' && e.filename != '..')
        .map((e) {
      final attrs = e.attr;
      final isDir = attrs.type == SftpFileType.directory;
      final size = attrs.size?.toInt() ?? 0;
      final modifiedMs = (attrs.modifyTime ?? 0) * 1000;
      return SshFileEntry(
        name: e.filename,
        path: '$remotePath/${e.filename}',
        isDirectory: isDir,
        size: size,
        modified: DateTime.fromMillisecondsSinceEpoch(modifiedMs),
      );
    }).toList();
  });

  /// Delete a remote file via SFTP.
  Future<void> deleteFile(String remotePath) => _withSftp((sftp) async {
    await sftp.remove(remotePath);
  });

  /// Create a remote directory via SFTP.
  Future<void> createDirectory(String remotePath) => _withSftp((sftp) async {
    await sftp.mkdir(remotePath);
  });

  /// Rename/move a remote path via SFTP.
  Future<void> rename(String oldPath, String newPath) => _withSftp((sftp) async {
    await sftp.rename(oldPath, newPath);
  });

  // ── Shell / process ────────────────────────────────────────────────────────

  /// Execute a single command on the remote host and return its stdout output.
  Future<String> execute(String command) async {
    _requireConnected();
    final session = await _client!.execute(command);
    final chunks = <Uint8List>[];
    await for (final chunk in session.stdout) {
      chunks.add(chunk);
    }
    await session.done;
    final bytes = chunks.fold<List<int>>([], (acc, c) => acc..addAll(c));
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// Start an interactive shell session. Returns an [SSHSession].
  Future<SSHSession> startShell() async {
    _requireConnected();
    return _client!.shell(
      pty: const SSHPtyConfig(
        type: 'xterm-256color',
        width: 80,
        height: 24,
      ),
    );
  }

  /// Start a process on the remote host (for LSP/DAP use).
  ///
  /// Uses `env` to prepend common binary locations to PATH so tools like
  /// `dart`, `node`, `python` are found in non-interactive SSH sessions
  /// without sourcing login scripts (which can write to stdout and corrupt
  /// the LSP Content-Length framing in the bridge).
  Future<SSHSession> startProcess(String command) async {
    _requireConnected();
    if (_remoteIsWindows) {
      // PowerShell doesn't support `export`. SDKs are already in PATH on
      // Windows (detected via where.exe), so just run the command directly.
      return _client!.execute(command);
    }
    // Common install prefixes — covers standard Linux, Termux, pub-cache, nvm.
    const extraPaths = [
      '/usr/local/bin',
      '/usr/bin',
      '/bin',
      r'$HOME/.pub-cache/bin',
      r'$HOME/flutter/bin',
      r'$HOME/.dart/bin',
      r'$HOME/.nvm/versions/node/*/bin',
      '/data/data/com.termux/files/usr/bin',
    ];
    final pathPrefix = extraPaths.join(':');
    return _client!.execute(
        'export PATH="$pathPrefix:\$PATH"; $command');
  }

  /// Returns the underlying [SSHClient] for advanced use cases.
  SSHClient? getSshClient() => _client;

  // ── Private helpers ────────────────────────────────────────────────────────

  void _requireConnected() {
    if (_client == null || _status != SshStatus.connected) {
      throw StateError('SSH client is not connected');
    }
  }

  /// Load SSH identities from a PEM key file path.
  List<SSHKeyPair>? _loadIdentities(String keyPath) {
    try {
      final file = File(keyPath);
      if (!file.existsSync()) return null;
      final pem = file.readAsStringSync();
      return SSHKeyPair.fromPem(pem);
    } catch (_) {
      return null;
    }
  }

  /// Load and parse an OpenSSH/PEM private key from [keyPath].
  static Future<List<SSHKeyPair>> loadIdentities(String keyPath) async {
    final pem = await File(keyPath).readAsString();
    return SSHKeyPair.fromPem(pem);
  }

  @override
  void dispose() {
    _keepAliveTimer?.cancel();
    _closeSftp();
    _client?.close();
    super.dispose();
  }
}
