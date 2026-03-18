import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

enum RootfsState { checking, notInstalled, downloading, extracting, ready, error }

class RootfsProvider extends ChangeNotifier {
  RootfsState _state = RootfsState.checking;
  double _progress = 0.0;
  String _statusMessage = '';
  String? _error;

  RootfsState get state => _state;
  double get progress => _progress;
  String get statusMessage => _statusMessage;
  String? get error => _error;
  bool get isReady => _state == RootfsState.ready;

  // GitHub repo that publishes the termux bootstrap ZIPs as release assets
  static const _kOwner  = 'termux';
  static const _kRepo   = 'termux-packages';
  static const _kAsset  = 'bootstrap-aarch64.zip';

  // Fallback URLs tried in order if the API lookup fails
  static const _kFallbackUrls = [
    'https://github.com/termux/termux-packages/releases/download/bootstrap-2024.07.01/$_kAsset',
    'https://github.com/termux/termux-packages/releases/download/bootstrap-2024.01.24/$_kAsset',
    'https://github.com/termux/termux-packages/releases/download/bootstrap-2023.06.15/$_kAsset',
  ];

  void checkBootstrap() {
    _state = RootfsState.checking;
    notifyListeners();

    if (RuntimeEnvir.isBootstrapped) {
      _fixPermissionsIfNeeded().then((_) {
        _state = RootfsState.ready;
        _statusMessage = 'RootFS ready';
        notifyListeners();
      });
    } else {
      _state = RootfsState.notInstalled;
      _statusMessage = 'RootFS not installed';
      notifyListeners();
    }
  }

  /// Ensures the shell binary is executable. Runs chmod only when the execute
  /// bit is missing, so it's a no-op on a correctly installed bootstrap.
  Future<void> _fixPermissionsIfNeeded() async {
    final bash = File(RuntimeEnvir.bashPath);
    if (!bash.existsSync()) return;
    final stat = bash.statSync();
    // mode & 0x40 = owner execute bit
    final ownerExec = stat.mode & 0x40;
    if (ownerExec == 0) {
      // Permissions are broken — fix the whole usr tree.
      await _chmodExecutables();
    }
  }

  Future<void> downloadAndInstall() async {
    try {
      // Step 1: Create directories
      _setState(RootfsState.downloading, 'Preparing directories...', 0.0);
      await _createDirectories();

      // Step 2: Resolve the latest bootstrap URL
      _setState(RootfsState.downloading, 'Resolving download URL...', 0.02);
      final url = await _resolveBootstrapUrl();

      // Step 3: Download
      _setState(RootfsState.downloading, 'Downloading bootstrap...', 0.05);
      final zipBytes = await _downloadBootstrap(url);

      // Step 4: Extract
      _setState(RootfsState.extracting, 'Extracting files...', 0.7);
      await _extractBootstrap(zipBytes);

      // Step 5: Run init script
      _setState(RootfsState.extracting, 'Setting up environment...', 0.9);
      await _runInitScript();

      _setState(RootfsState.ready, 'RootFS ready!', 1.0);
    } catch (e) {
      _error = e.toString();
      _state = RootfsState.error;
      _statusMessage = 'Error: $e';
      notifyListeners();
    }
  }

  /// Queries the GitHub Releases API to find the latest release that contains
  /// [_kAsset] and returns its download URL.
  /// Falls back to [_kFallbackUrls] if the API is unreachable or rate-limited.
  Future<String> _resolveBootstrapUrl() async {
    final dio = Dio();
    try {
      final resp = await dio.get<List<dynamic>>(
        'https://api.github.com/repos/$_kOwner/$_kRepo/releases',
        queryParameters: {'per_page': 20},
        options: Options(
          headers: {'Accept': 'application/vnd.github+json'},
          receiveTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 10),
        ),
      );

      for (final release in resp.data!) {
        final assets = (release['assets'] as List<dynamic>?) ?? [];
        for (final asset in assets) {
          if ((asset['name'] as String?) == _kAsset) {
            final url = asset['browser_download_url'] as String?;
            if (url != null && url.isNotEmpty) return url;
          }
        }
      }
    } catch (_) {
      // API unavailable — fall through to hardcoded fallbacks
    }

    // Try each fallback URL with a HEAD request to verify it exists
    for (final url in _kFallbackUrls) {
      try {
        final head = await dio.head<void>(
          url,
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            validateStatus: (s) => s != null && s < 400,
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        if ((head.statusCode ?? 0) < 400) return url;
      } catch (_) {
        continue;
      }
    }

    throw Exception(
      'Could not find a working bootstrap URL.\n'
      'Check your internet connection and try again.',
    );
  }

  Future<void> _createDirectories() async {
    for (final path in [
      RuntimeEnvir.filesPath,
      RuntimeEnvir.usrPath,
      RuntimeEnvir.homePath,
      RuntimeEnvir.projectsPath,
      '${RuntimeEnvir.usrPath}/bin',
      '${RuntimeEnvir.usrPath}/lib',
      '${RuntimeEnvir.usrPath}/etc',
      '${RuntimeEnvir.homePath}/.pub-cache',
    ]) {
      await Directory(path).create(recursive: true);
    }
  }

  Future<Uint8List> _downloadBootstrap(String url) async {
    final dio = Dio();
    final response = await dio.get<ResponseBody>(
      url,
      options: Options(
        responseType: ResponseType.stream,
        followRedirects: true,
        maxRedirects: 10,
      ),
    );

    final contentLength =
        int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
    final bytes = <int>[];

    await for (final chunk in response.data!.stream) {
      bytes.addAll(chunk);
      if (contentLength > 0) {
        final dl = 0.05 + (bytes.length / contentLength) * 0.6;
        _setState(
          RootfsState.downloading,
          'Downloading... ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
          dl.clamp(0.05, 0.65),
        );
      }
    }

    return Uint8List.fromList(bytes);
  }

  Future<void> _extractBootstrap(Uint8List zipBytes) async {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final total = archive.files.length;
    var done = 0;

    for (final file in archive) {
      final filePath = '${RuntimeEnvir.usrPath}/${file.name}';

      if (file.isFile) {
        final outFile = File(filePath);
        await outFile.create(recursive: true);
        await outFile.writeAsBytes(file.content as List<int>);

        // Apply Unix permissions from the ZIP entry (lower 9 bits = rwxrwxrwx).
        // The archive package preserves them in file.mode but dart:io doesn't
        // apply them on write — without this, all binaries end up as 0644
        // (no execute bit) and execvp returns EACCES.
        final unixMode = file.mode & 0x1FF;
        if (unixMode != 0) {
          final modeStr = unixMode.toRadixString(8).padLeft(3, '0');
          await Process.run('/system/bin/chmod', [modeStr, filePath]);
        }
      } else {
        await Directory(filePath).create(recursive: true);
      }

      done++;
      final p = 0.7 + (done / total) * 0.18;
      _setState(RootfsState.extracting,
          'Extracting... $done/$total', p.clamp(0.7, 0.88));
    }

    // Belt-and-suspenders: make sure every binary in bin/ and lib/ is
    // executable regardless of what the ZIP metadata said.
    await _chmodExecutables();
  }

  Future<void> _chmodExecutables() async {
    final targets = [
      '${RuntimeEnvir.usrPath}/bin',
      '${RuntimeEnvir.usrPath}/lib',
      '${RuntimeEnvir.usrPath}/libexec',
    ];
    for (final dir in targets) {
      if (Directory(dir).existsSync()) {
        await Process.run('/system/bin/chmod', ['-R', '755', dir]);
      }
    }
  }

  Future<void> _runInitScript() async {
    // Create symlinks from SYMLINKS.txt if present
    final symlinksFile = File('${RuntimeEnvir.usrPath}/SYMLINKS.txt');
    if (await symlinksFile.exists()) {
      final lines = await symlinksFile.readAsLines();
      for (final line in lines) {
        final parts = line.split('←');
        if (parts.length == 2) {
          final target   = parts[0].trim();
          final linkPath = '${RuntimeEnvir.usrPath}/${parts[1].trim()}';
          try {
            final link = Link(linkPath);
            if (!await link.exists()) await link.create(target);
          } catch (_) {}
        }
      }
    }

    // Write a basic .bashrc if not present
    final bashrc = File('${RuntimeEnvir.homePath}/.bashrc');
    if (!await bashrc.exists()) {
      await bashrc.writeAsString('''
export HOME="${RuntimeEnvir.homePath}"
export PREFIX="${RuntimeEnvir.usrPath}"
export PATH="\$PREFIX/bin:\$PREFIX/bin/applets:\$PATH"
export TERM=xterm-256color
export LANG=en_US.UTF-8

# Flutter
export FLUTTER_ROOT="${RuntimeEnvir.flutterPath}"
export PATH="\$FLUTTER_ROOT/bin:\$PATH"

# Android SDK
export ANDROID_HOME="${RuntimeEnvir.androidSdkPath}"
export PATH="\$ANDROID_HOME/tools/bin:\$ANDROID_HOME/platform-tools:\$PATH"

echo "FL IDE environment ready"
''');
    }
  }

  void _setState(RootfsState s, String msg, double p) {
    _state = s;
    _statusMessage = msg;
    _progress = p;
    notifyListeners();
  }

  void retry() {
    _error = null;
    downloadAndInstall();
  }
}
