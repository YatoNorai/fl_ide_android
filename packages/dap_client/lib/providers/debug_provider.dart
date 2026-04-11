import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

export 'package:core/core.dart' show DapConfig;

import '../client/dap_client_base.dart';
import '../client/dap_stdio_client.dart';
import '../client/dap_tcp_client.dart';
import '../models/dap_types.dart';

export '../models/dap_types.dart';

// ── Status ────────────────────────────────────────────────────────────────────

enum DebugStatus { idle, starting, running, paused, terminating }

// ── Provider ──────────────────────────────────────────────────────────────────

class DebugProvider extends ChangeNotifier {
  DapClientBase? _client;
  // For TCP mode (e.g. dlv dap): the adapter process is separate from _client.
  Process? _adapterProcess;
  StreamSubscription<Map<String, dynamic>>? _eventSub;
  Process? _metroProcess;
  bool _isMetroSession = false;

  DebugStatus _status = DebugStatus.idle;
  String _output = '';
  String? _error;

  // Breakpoints: absolute file path → list of 1-based line numbers.
  final Map<String, List<int>> _breakpoints = {};
  // Exception breakpoint filters
  bool _breakOnAllExceptions = false;
  bool _breakOnUncaughtExceptions = true;

  // Watch expressions: expression → evaluated result string
  final List<String> _watchExpressions = [];
  final Map<String, String> _watchResults = {};

  // State when paused
  List<DapThread> _threads = [];
  List<DapStackFrame> _callStack = [];
  List<DapScope> _scopes = [];
  List<DapVariable> _variables = [];
  String? _stopReason;
  String? _stoppedFile;
  int? _stoppedLine;
  int? _currentThreadId;
  int? _currentFrameId;

  // Session context
  String _projectPath = '';
  String _platformArg = 'android';
  DapConfig _dapConfig = DapConfig.empty;
  String? _webServerUrl;
  bool _isBuilding = false;
  Project? _currentMetroProject; // kept for Metro restart

  /// Fixed port used when launching the Flutter web-server device.
  static const int webServerPort = 5050;

  /// Set when the web-server device is running and the URL is known.
  /// Listeners can watch this to auto-open a WebView preview.
  String? get webServerUrl => _webServerUrl;

  /// True while the current session is a Metro (React Native / Expo) run,
  /// not a DAP session. Used by the WebPreviewOverlay to adapt its toolbar.
  bool get isMetroSession => _isMetroSession;

  // ── Getters ───────────────────────────────────────────────────────────────

  DebugStatus get status => _status;
  bool get isActive => _status != DebugStatus.idle;
  bool get isPaused => _status == DebugStatus.paused;
  bool get isRunning => _status == DebugStatus.running;
  bool get isBuilding => _isBuilding;
  String get output => _output;
  String? get error => _error;
  List<DapThread> get threads => _threads;
  List<DapStackFrame> get callStack => _callStack;
  List<DapScope> get scopes => _scopes;
  List<DapVariable> get variables => _variables;
  String? get stopReason => _stopReason;
  String? get stoppedFile => _stoppedFile;
  int? get stoppedLine => _stoppedLine;
  int? get currentFrameId => _currentFrameId;
  Map<String, List<int>> get breakpoints => Map.unmodifiable(_breakpoints);

  List<int> breakpointsForFile(String filePath) =>
      List.unmodifiable(_breakpoints[filePath] ?? []);
  bool get breakOnAllExceptions => _breakOnAllExceptions;
  bool get breakOnUncaughtExceptions => _breakOnUncaughtExceptions;
  List<String> get watchExpressions => List.unmodifiable(_watchExpressions);
  Map<String, String> get watchResults => Map.unmodifiable(_watchResults);

  // ── Session lifecycle ─────────────────────────────────────────────────────

  Future<void> startSession(
    Project project, {
    String platform = 'android',
    DapConfig? dapConfig,
  }) async {
    if (_status != DebugStatus.idle) return;
    _error = null;
    _output = '';
    _projectPath = project.path;
    _platformArg = platform;
    // Prefer caller-supplied config; fall back to built-in Flutter defaults.
    _dapConfig = dapConfig ?? _flutterFallbackDapConfig;
    _status = DebugStatus.starting;
    _isBuilding = true;
    notifyListeners();

    try {
      final adapterBin = _dapConfig.resolvedBinary;
      if (adapterBin.isEmpty) {
        throw DapException('No DAP adapter configured for this SDK.');
      }
      if (!File(adapterBin).existsSync()) {
        throw DapException('DAP adapter binary not found at $adapterBin');
      }

      await _startStdioSession(adapterBin);
    } catch (e) {
      _error = e.toString();
      debugPrint('[DAP] startSession error: $e');
      await _cleanup();
    }
  }

  Future<void> _startStdioSession(String adapterBin) async {
    final stdioClient = DapStdioClient();
    _client = stdioClient;
    await stdioClient.start(
      adapterBin,
      _dapConfig.adapterArgs,
      RuntimeEnvir.baseEnv,
      onStderr: (line) {
        _output += '[adapter] $line\n';
        notifyListeners();
      },
    );
    _eventSub = _client!.events.listen(_onEvent);
    await _sendInitialize();
  }

  /// Starts a TCP-mode DAP adapter (e.g. `dlv dap --listen=127.0.0.1:PORT`).
  ///
  /// We pick the port ourselves by briefly binding a socket, so we never
  /// need to parse the adapter's stderr output for the port — that output
  /// format varies across dlv versions and may be buffered on Termux.
  Future<void> _startTcpSession(String adapterBin) async {
    // Find a free port: bind to :0, record the port, release the socket.
    // The gap between close() and dlv binding is tiny on a single-user device.
    final int port;
    {
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      port = probe.port;
      await probe.close();
    }

    // Replace the placeholder `:0` in adapter args with the chosen port.
    // e.g. "--listen=127.0.0.1:0" → "--listen=127.0.0.1:PORT"
    final args = _dapConfig.adapterArgs
        .map((a) => a.replaceAll(':0', ':$port'))
        .toList();

    _adapterProcess = await Process.start(
      adapterBin,
      args,
      environment: RuntimeEnvir.baseEnv,
      runInShell: true,
    );

    _adapterProcess!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          debugPrint('[DAP adapter stderr] $line');
          _output += '[adapter] $line\n';
          notifyListeners();
        });

    _adapterProcess!.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen((chunk) {
          _output += chunk;
          notifyListeners();
        });

    // Give dlv time to bind the port before we connect.
    await Future<void>.delayed(const Duration(milliseconds: 800));

    if (_adapterProcess == null) {
      // Process exited during the delay — cleanup will have been triggered.
      throw DapException('DAP adapter exited before the IDE could connect');
    }

    final tcpClient = DapTcpClient();
    _client = tcpClient;
    await tcpClient.connect('127.0.0.1', port);
    _eventSub = _client!.events.listen(_onEvent);
    await _sendInitialize();
  }

  Future<void> _sendInitialize() async {
    await _client!.sendRequest('initialize', {
      'clientID': 'fl_ide',
      'clientName': 'FL IDE',
      'adapterID': _dapConfig.adapterId.isEmpty ? 'dart' : _dapConfig.adapterId,
      'pathFormat': 'path',
      'linesStartAt1': true,
      'columnsStartAt1': true,
      'supportsVariableType': true,
      'supportsVariablePaging': false,
      'supportsRunInTerminalRequest': false,
      'supportsInvalidatedEvent': true,
    }).timeout(const Duration(seconds: 30));
    // _onInitialized() handles steps 2-4 when 'initialized' event arrives.
  }

  /// Start a debug session with a DAP adapter running on a remote machine
  /// over SSH. [remoteStdout] / [remoteStdin] are the SSH process stdio.
  Future<void> startSessionRemote(
    Project project, {
    required Stream<Uint8List> remoteStdout,
    required StreamSink<Uint8List> remoteStdin,
    String platform = 'android',
    DapConfig? dapConfig,
  }) async {
    if (_status != DebugStatus.idle) return;
    _error = null;
    _output = '';
    _projectPath = project.path;
    _platformArg = platform;
    _dapConfig = dapConfig ?? _flutterFallbackDapConfig;
    _status = DebugStatus.starting;
    _isBuilding = true;
    notifyListeners();

    try {
      final stdioClient = DapStdioClient();
      _client = stdioClient;
      await stdioClient.startRemote(remoteStdout, remoteStdin, onStderr: (line) {
        _output += '[adapter] $line\n';
        notifyListeners();
      });
      _eventSub = _client!.events.listen(_onEvent);
      await _sendInitialize();
    } catch (e) {
      _error = e.toString();
      debugPrint('[DAP SSH] startSessionRemote error: $e');
      await _cleanup();
    }
  }

  /// Kill any process occupying [port] so the next `flutter run` web session
  /// can bind to it. Uses `fuser -k` (Linux/Android) with a SIGKILL fallback
  /// via `lsof`. Errors are silently swallowed — if neither tool exists the
  /// port may still be free anyway.
  static Future<void> _freePort(int port) async {
    try {
      // fuser is available on most Termux / Linux systems.
      final r = await Process.run('fuser', ['-k', '$port/tcp']);
      if (r.exitCode == 0) {
        // Give the OS a moment to release the socket.
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return;
      }
    } catch (_) {}
    try {
      // Fallback: lsof + kill
      await Process.run('sh', [
        '-c',
        'lsof -ti:$port | xargs -r kill -9 2>/dev/null; true',
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 400));
    } catch (_) {}
  }

  /// Start a Metro bundler session for React Native / Expo projects.
  /// This is used instead of a DAP session when no DAP adapter is available.
  Future<void> startMetroSession(Project project) async {
    if (_status != DebugStatus.idle) return;
    _error = null;
    _output = '';
    _projectPath = project.path;
    _status = DebugStatus.starting;
    _isBuilding = true;
    _isMetroSession = true;
    _currentMetroProject = project;
    notifyListeners();

    try {
      // Detect Expo vs bare React Native
      bool isExpo = false;
      try {
        final pkgRaw = await File('${project.path}/package.json').readAsString();
        isExpo = pkgRaw.contains('"expo"');
      } catch (_) {}

      final args = isExpo
          ? ['expo', 'start', '--localhost']
          : ['react-native', 'start'];

      _output += isExpo
          ? 'Iniciando Expo Metro bundler...\n'
          : 'Iniciando React Native Metro bundler...\n';
      notifyListeners();

      // ── Termux ENOSPC fix ─────────────────────────────────────────────────
      // Default Android inotify limit ≈ 8 192 watches. An Expo project has
      // 30 000+ subdirectories in node_modules. Crashed Metro runs leave
      // zombie processes holding all their watches until the kernel GCs them,
      // so even the very first fs.watch() call fails with ENOSPC.
      //
      // Strategy (no root required):
      //   1. Kill zombie Metro / Expo Node processes → watches freed.
      //   2. Write a Node.js --require preload that patches fs.watch to:
      //        a. Return a no-op watcher for node_modules paths (no inotify).
      //        b. Swallow ENOSPC for any other path instead of crashing.
      //   3. Try bumping the kernel limit via /proc (silent fail without root).

      // Step 1 — kill zombies
      _output += '[Metro] Liberando watches de sessões anteriores...\n';
      notifyListeners();
      try {
        await Process.run(
          'sh',
          [
            '-c',
            'pkill -9 -f "expo start"     2>/dev/null; '
            'pkill -9 -f "metro-file-map" 2>/dev/null; '
            'pkill -9 -f "@expo/cli"      2>/dev/null; '
            'sleep 1.5',
          ],
          environment: RuntimeEnvir.baseEnv,
        );
      } catch (_) {}

      // Step 2 — write the fs.watch preload script
      // Using CommonJS (.cjs) so it works whether the project is ESM or CJS.
      // The file is idempotent: overwriting it on every start is harmless.
      const _kPreload = r"""
'use strict';
const fs = require('fs');
const { EventEmitter } = require('events');

function _fakeWatcher() {
  const w = new EventEmitter();
  w.close = () => {};
  return w;
}

const _origWatch = fs.watch;
fs.watch = function (filename, options, listener) {
  if (
    typeof filename === 'string' &&
    (filename.includes('/node_modules/') || filename.endsWith('/node_modules'))
  ) {
    return _fakeWatcher(); // skip node_modules — no inotify consumed
  }
  try {
    return _origWatch.call(this, filename, options, listener);
  } catch (e) {
    if (e.code === 'ENOSPC') {
      // Limit hit for a source dir — degrade gracefully (no hot-reload for
      // this dir, but Metro keeps running instead of crashing).
      return _fakeWatcher();
    }
    throw e;
  }
};
""";

      final preloadPath = '${project.path}/.metro-termux-fix.cjs';
      try {
        await File(preloadPath).writeAsString(_kPreload);
      } catch (_) {}

      // Step 3 — try bumping the limit (works on some Android kernels)
      try {
        await Process.run('sh', [
          '-c',
          'echo 65536 > /proc/sys/fs/inotify/max_user_watches 2>/dev/null || true',
        ]);
      } catch (_) {}

      // Inject preload via NODE_OPTIONS so it runs before any Metro code
      final existingOpts = RuntimeEnvir.baseEnv['NODE_OPTIONS'] ?? '';
      final nodeOptions = existingOpts.isEmpty
          ? '--require $preloadPath'
          : '$existingOpts --require $preloadPath';

      final env = <String, String>{
        ...RuntimeEnvir.baseEnv,
        'NODE_OPTIONS': nodeOptions,
      };

      _metroProcess = await Process.start(
        'npx', args,
        workingDirectory: project.path,
        environment: env,
      );

      const buildDoneMarkers = [
        'Metro waiting on',
        'Scan the QR code',
        'Bundler ready',
        'Development server started',
        'Ready!',
      ];

      void handleChunk(String chunk) {
        _output += chunk;
        if (_isBuilding && buildDoneMarkers.any(chunk.contains)) {
          _isBuilding = false;
          _status = DebugStatus.running;
          // Signal the workspace to open the WebPreviewOverlay.
          // Expo / Metro serves at :8081. For Expo we append ?platform=web
          // so the WebView renders the React Native web app (react-native-web).
          _webServerUrl = isExpo
              ? 'http://localhost:8081/?platform=web'
              : 'http://localhost:8081';
        }
        notifyListeners();
      }

      _metroProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(handleChunk);
      _metroProcess!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(handleChunk);

      _metroProcess!.exitCode.then((_) {
        if (_status != DebugStatus.idle) Future.microtask(_cleanup);
      });

      // Timeout: assume running after 60s even if no marker found
      Future.delayed(const Duration(seconds: 60), () {
        if (_isBuilding) {
          _isBuilding = false;
          if (_status == DebugStatus.starting) _status = DebugStatus.running;
          _webServerUrl ??= isExpo
              ? 'http://localhost:8081/?platform=web'
              : 'http://localhost:8081';
          notifyListeners();
        }
      });
    } catch (e) {
      _error = e.toString();
      debugPrint('[Metro] startMetroSession error: $e');
      await _cleanup();
    }
  }


  Future<void> stopSession() async {
    if (_status == DebugStatus.idle) return;
    _status = DebugStatus.terminating;
    notifyListeners();
    _metroProcess?.kill();
    _metroProcess = null;
    try {
      await _client?.sendRequest('disconnect', {'terminateDebuggee': true})
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _cleanup();
  }

  Future<void> _cleanup() async {
    _metroProcess?.kill();
    _metroProcess = null;
    _adapterProcess?.kill();
    _adapterProcess = null;
    await _eventSub?.cancel();
    _eventSub = null;
    await _client?.dispose();
    _client = null;
    _reset();
  }

  // ── Event handler ─────────────────────────────────────────────────────────

  void _onEvent(Map<String, dynamic> msg) {
    final event = msg['event'] as String? ?? '';
    final body = (msg['body'] as Map<String, dynamic>?) ?? {};

    switch (event) {
      case 'initialized':
        _onInitialized();
      case 'stopped':
        _onStopped(body);
      case 'continued':
        _status = DebugStatus.running;
        _stoppedLine = null;
        _stoppedFile = null;
        _callStack = [];
        _variables = [];
        notifyListeners();
      case 'thread':
        _onThreadEvent(body);
      case 'output':
        final text = body['output'] as String? ?? '';
        if (text.isNotEmpty) {
          _output += text;
          // Detect web-server URL from output, e.g.: "http://localhost:5050"
          final webPlatform = _dapConfig.webPlatform;
          if (_webServerUrl == null &&
              webPlatform.isNotEmpty &&
              _platformArg == webPlatform) {
            final urlMatch = RegExp(r'http://localhost:\d+').firstMatch(text);
            if (urlMatch != null) {
              _webServerUrl = urlMatch.group(0);
              _isBuilding = false;
            }
          }
          if (_isBuilding) {
            final doneStrings = _dapConfig.buildDoneStrings.isNotEmpty
                ? _dapConfig.buildDoneStrings
                : _kDefaultBuildDoneStrings;
            if (doneStrings.any(text.contains)) {
              _isBuilding = false;
            }
          }
          notifyListeners();
        }
      case 'terminated':
      case 'exited':
        Future.microtask(_cleanup);
    }
  }

  Future<void> _onInitialized() async {
    try {
      // 2. Send all pending breakpoints
      for (final entry in _breakpoints.entries) {
        await _sendBreakpointsToAdapter(entry.key, entry.value);
      }
      // 2b. Send exception breakpoints
      await _sendExceptionBreakpoints();
      // 3. Configuration done
      await _client!.sendRequest('configurationDone')
          .timeout(const Duration(seconds: 10));

      // 4. Build launch args from DapConfig
      final Map<String, dynamic> launchArgs;

      if (_dapConfig.adapterId == 'go') {
        // Delve (dlv dap) launch: program + cwd, no device/platform concepts.
        final program = _dapConfig.launchProgram.isNotEmpty
            ? _dapConfig.launchProgram
            : '.';
        _output += 'Launching Go program ($program) with Delve...\n';
        notifyListeners();
        launchArgs = {
          'mode': 'debug',
          'program': program,
          'cwd': _projectPath,
          'noDebug': false,
        };
      } else {
        final program = _dapConfig.launchProgram.isNotEmpty
            ? _dapConfig.launchProgram
            : 'lib/main.dart';
        final deviceId = _dapConfig.deviceIdFor(_platformArg);

        _output += 'Launching $program on $deviceId...\n';
        notifyListeners();

        launchArgs = {
          'program': program,
          'cwd': _projectPath,
          'debugSdkLibraries': false,
          'debugExternalPackageLibraries': false,
          'noDebug': false,
        };

        if (_dapConfig.webPlatform.isNotEmpty && _platformArg == _dapConfig.webPlatform) {
          // Free the port before binding so stale flutter-web processes don't
          // block the new session (errno 98 = EADDRINUSE).
          await _freePort(webServerPort);

          // Web platform: pass toolArgs so the adapter finds the device without
          // device-list discovery (web-server isn't enumerated by flutter devices).
          launchArgs['toolArgs'] = _dapConfig.webServerArgs.isNotEmpty
              ? _dapConfig.webServerArgs
              : [
                  '-d', 'web-server',
                  '--web-port', '$webServerPort',
                  '--web-hostname', 'localhost',
                  '--no-start-paused',
                ];
        } else if (deviceId.isNotEmpty) {
          // Native device: validate availability before launching.
          final devsCmd = _dapConfig.resolvedDevicesCommand;
          if (devsCmd.isNotEmpty) {
            final available = await _getAvailableDeviceIds(devsCmd);
            if (!available.any((id) => id == deviceId || id.startsWith('$deviceId-'))) {
              _output += '[DAP] Error: device "$deviceId" not found.\n'
                  'Available: ${available.isEmpty ? "none" : available.join(", ")}\n'
                  'Connect a device or change the debug platform in Settings.\n';
              notifyListeners();
              await _cleanup();
              return;
            }
          }
          launchArgs['deviceId'] = deviceId;
        }
      }

      await _client!.sendRequest('launch', launchArgs)
          .timeout(const Duration(seconds: 60));
      _status = DebugStatus.running;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      debugPrint('[DAP] _onInitialized error: $e');
      await _cleanup();
    }
  }

  Future<void> _onStopped(Map<String, dynamic> body) async {
    _status = DebugStatus.paused;
    _stopReason = body['reason'] as String?;
    _currentThreadId = body['threadId'] as int? ?? 1;
    notifyListeners();
    await _fetchCallStack();
  }

  void _onThreadEvent(Map<String, dynamic> body) {
    // We'll refresh thread list on next stackTrace fetch
    final id = body['threadId'] as int?;
    final reason = body['reason'] as String?;
    if (reason == 'exited' && id != null) {
      _threads.removeWhere((t) => t.id == id);
      notifyListeners();
    }
  }

  // ── Debug commands ────────────────────────────────────────────────────────

  Future<void> continueExec() async {
    if (_client == null || !isPaused) return;
    await _client!.sendRequest('continue', {
      'threadId': _currentThreadId ?? 1,
    });
  }

  Future<void> stepOver() async {
    if (_client == null || !isPaused) return;
    await _client!.sendRequest('next', {
      'threadId': _currentThreadId ?? 1,
      'granularity': 'statement',
    });
  }

  Future<void> stepIn() async {
    if (_client == null || !isPaused) return;
    await _client!.sendRequest('stepIn', {
      'threadId': _currentThreadId ?? 1,
      'granularity': 'statement',
    });
  }

  Future<void> stepOut() async {
    if (_client == null || !isPaused) return;
    await _client!.sendRequest('stepOut', {
      'threadId': _currentThreadId ?? 1,
      'granularity': 'statement',
    });
  }

  Future<void> pause() async {
    if (_client == null || !isRunning) return;
    await _client!.sendRequest('pause', {
      'threadId': _currentThreadId ?? 1,
    });
  }

  Future<void> restart() async {
    if (_isMetroSession) {
      await restartMetro();
      return;
    }
    if (_client == null || !isActive) return;
    await _client!.sendRequest('restart');
  }

  Future<void> hotReload() async {
    if (_isMetroSession) {
      await hotReloadMetro();
      return;
    }
    if (_client == null || !isRunning) return;
    try {
      await _client!.sendRequest('hotReload', {});
    } catch (e) {
      debugPrint('[DAP] hotReload error: $e');
    }
  }

  /// Triggers a JS reload on the Metro dev server (React Native / Expo).
  /// Metro listens for POST /reload requests from tooling.
  Future<void> hotReloadMetro() async {
    try {
      final client = HttpClient();
      final req = await client
          .postUrl(Uri.parse('http://localhost:8081/reload'))
          .timeout(const Duration(seconds: 5));
      await req.close();
    } catch (e) {
      debugPrint('[Metro] hotReload POST failed: $e');
    }
  }

  /// Kills and restarts the Metro bundler for the current project.
  Future<void> restartMetro() async {
    final project = _currentMetroProject;
    if (project == null) return;
    await stopSession();
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await startMetroSession(project);
  }

  // ── Breakpoints ───────────────────────────────────────────────────────────

  /// Toggle a breakpoint at [line] (1-based) in [filePath].
  void toggleBreakpoint(String filePath, int line) {
    final lines = List<int>.from(_breakpoints[filePath] ?? []);
    if (lines.contains(line)) {
      lines.remove(line);
    } else {
      lines.add(line);
      lines.sort();
    }
    _breakpoints[filePath] = lines;
    if (_client != null) {
      _sendBreakpointsToAdapter(filePath, lines).ignore();
    }
    notifyListeners();
  }

  /// Replace all breakpoints for [filePath] (used for bulk sync from editor).
  void setBreakpointsForFile(String filePath, Set<int> lines) {
    final sorted = lines.toList()..sort();
    _breakpoints[filePath] = sorted;
    if (_client != null) {
      _sendBreakpointsToAdapter(filePath, sorted).ignore();
    }
    notifyListeners();
  }

  // ── Exception breakpoints ─────────────────────────────────────────────────

  void setBreakOnAllExceptions(bool value) {
    _breakOnAllExceptions = value;
    if (_client != null) _sendExceptionBreakpoints().ignore();
    notifyListeners();
  }

  void setBreakOnUncaughtExceptions(bool value) {
    _breakOnUncaughtExceptions = value;
    if (_client != null) _sendExceptionBreakpoints().ignore();
    notifyListeners();
  }

  Future<void> _sendExceptionBreakpoints() async {
    if (_client == null) return;
    try {
      final filters = <String>[
        if (_breakOnAllExceptions) 'all',
        if (_breakOnUncaughtExceptions) 'uncaught',
      ];
      await _client!.sendRequest('setExceptionBreakpoints', {'filters': filters});
    } catch (e) {
      debugPrint('[DAP] setExceptionBreakpoints error: $e');
    }
  }

  // ── Watch expressions ─────────────────────────────────────────────────────

  void addWatch(String expression) {
    if (expression.trim().isEmpty) return;
    if (_watchExpressions.contains(expression)) return;
    _watchExpressions.add(expression);
    notifyListeners();
    if (isPaused) _evaluateWatch(expression).ignore();
  }

  void removeWatch(String expression) {
    _watchExpressions.remove(expression);
    _watchResults.remove(expression);
    notifyListeners();
  }

  Future<void> _evaluateWatch(String expression) async {
    final result = await evaluate(expression);
    _watchResults[expression] = result;
    if (mounted) notifyListeners();
  }

  bool get mounted => true; // ChangeNotifier doesn't have mounted; used as guard

  Future<void> evaluateAllWatches() async {
    if (!isPaused || _watchExpressions.isEmpty) return;
    for (final expr in _watchExpressions) {
      await _evaluateWatch(expr);
    }
  }

  Future<void> _sendBreakpointsToAdapter(
      String filePath, List<int> lines) async {
    if (_client == null) return;
    try {
      await _client!.sendRequest('setBreakpoints', {
        'source': {'path': filePath},
        'breakpoints': lines.map((l) => {'line': l}).toList(),
        'lines': lines,
      });
    } catch (e) {
      debugPrint('[DAP] setBreakpoints error: $e');
    }
  }

  // ── Call stack & variables ────────────────────────────────────────────────

  Future<void> _fetchCallStack() async {
    if (_client == null || _currentThreadId == null) return;
    try {
      final body = await _client!.sendRequest('stackTrace', {
        'threadId': _currentThreadId,
        'startFrame': 0,
        'levels': 20,
      });
      final frames =
          (body['stackFrames'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _callStack = frames.map(DapStackFrame.fromJson).toList();

      if (_callStack.isNotEmpty) {
        final top = _callStack.first;
        _currentFrameId = top.id;
        _stoppedFile = top.sourcePath;
        _stoppedLine = top.line;
        await _fetchScopes(top.id);
      }
    } catch (e) {
      debugPrint('[DAP] fetchCallStack error: $e');
    }
    notifyListeners();
    // Re-evaluate all watch expressions at the new stop location.
    evaluateAllWatches().ignore();
  }

  Future<void> selectFrame(DapStackFrame frame) async {
    _currentFrameId = frame.id;
    _stoppedFile = frame.sourcePath;
    _stoppedLine = frame.line;
    notifyListeners();
    await _fetchScopes(frame.id);
  }

  Future<void> _fetchScopes(int frameId) async {
    if (_client == null) return;
    try {
      final body = await _client!.sendRequest('scopes', {'frameId': frameId});
      final scopes =
          (body['scopes'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _scopes = scopes.map(DapScope.fromJson).toList();
      // Auto-load variables for the first non-expensive scope
      final first = _scopes.firstWhere(
        (s) => !s.expensive,
        orElse: () => _scopes.isNotEmpty ? _scopes.first : const DapScope(name: '', variablesReference: 0, expensive: false),
      );
      if (first.variablesReference > 0) {
        await fetchVariables(first.variablesReference);
      } else {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[DAP] fetchScopes error: $e');
      notifyListeners();
    }
  }

  Future<void> fetchVariables(int variablesReference) async {
    if (_client == null || variablesReference <= 0) return;
    try {
      final body = await _client!.sendRequest('variables', {
        'variablesReference': variablesReference,
      });
      final vars =
          (body['variables'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      _variables = vars.map(DapVariable.fromJson).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[DAP] fetchVariables error: $e');
    }
  }

  Future<String> evaluate(String expression) async {
    if (_client == null || _currentFrameId == null) return '';
    try {
      final body = await _client!.sendRequest('evaluate', {
        'expression': expression,
        'frameId': _currentFrameId,
        'context': 'watch',
      });
      return body['result'] as String? ?? '';
    } catch (e) {
      return 'Error: $e';
    }
  }

  // ── Device detection ──────────────────────────────────────────────────────

  /// Build-done strings used when [DapConfig.buildDoneStrings] is empty.
  static const _kDefaultBuildDoneStrings = [
    'Syncing files to device',
    'flutter run key commands',
    'Running with soundNullSafety',
    'To hot reload',
  ];

  /// Flutter DAP config used when no explicit [DapConfig] is supplied.
  static final _flutterFallbackDapConfig = DapConfig(
    adapterBinary: '${RuntimeEnvir.flutterPath}/bin/flutter',
    adapterArgs: const ['debug_adapter'],
    adapterId: 'dart',
    launchProgram: 'lib/main.dart',
    devicesCommand: '${RuntimeEnvir.flutterPath}/bin/flutter devices --machine',
    buildDoneStrings: _kDefaultBuildDoneStrings,
    platformDeviceMap: const {
      'android': 'android',
      'web': 'web-server',
      'linux': 'linux',
    },
    webPlatform: 'web',
    webServerArgs: const [
      '-d', 'web-server',
      '--web-port', '5050',
      '--web-hostname', 'localhost',
      '--no-start-paused',
    ],
  );

  /// Runs [devicesCmd] and returns device IDs from JSON output.
  /// [devicesCmd] is a full shell command, e.g. `flutter devices --machine`.
  Future<List<String>> _getAvailableDeviceIds(String devicesCmd) async {
    try {
      final parts = devicesCmd.split(' ');
      final result = await Process.run(
        parts.first,
        parts.skip(1).toList(),
        environment: RuntimeEnvir.baseEnv,
        runInShell: true,
      ).timeout(const Duration(seconds: 15));
      if (result.exitCode != 0) return [];
      final list = jsonDecode(result.stdout as String) as List?;
      return list
              ?.cast<Map<String, dynamic>>()
              .map((d) => d['id'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toList() ??
          [];
    } catch (_) {
      return [];
    }
  }

  // ── Reset ─────────────────────────────────────────────────────────────────

  void _reset() {
    _status = DebugStatus.idle;
    _threads = [];
    _callStack = [];
    _scopes = [];
    _variables = [];
    _watchResults.clear();
    _stopReason = null;
    _stoppedFile = null;
    _stoppedLine = null;
    _currentThreadId = null;
    _currentFrameId = null;
    _webServerUrl = null;
    _isBuilding = false;
    _isMetroSession = false;
    _currentMetroProject = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _metroProcess?.kill();
    _adapterProcess?.kill();
    _eventSub?.cancel();
    _client?.dispose();
    super.dispose();
  }
}
