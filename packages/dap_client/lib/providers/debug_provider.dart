import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

export 'package:core/core.dart' show DapConfig;

import '../client/dap_stdio_client.dart';
import '../models/dap_types.dart';

export '../models/dap_types.dart';

// ── Status ────────────────────────────────────────────────────────────────────

enum DebugStatus { idle, starting, running, paused, terminating }

// ── Provider ──────────────────────────────────────────────────────────────────

class DebugProvider extends ChangeNotifier {
  DapStdioClient? _client;
  StreamSubscription<Map<String, dynamic>>? _eventSub;

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

  /// Fixed port used when launching the Flutter web-server device.
  static const int webServerPort = 5050;

  /// Set when the web-server device is running and the URL is known.
  /// Listeners can watch this to auto-open a WebView preview.
  String? get webServerUrl => _webServerUrl;

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

      _client = DapStdioClient();
      await _client!.start(
        adapterBin,
        _dapConfig.adapterArgs,
        RuntimeEnvir.baseEnv,
        onStderr: (line) {
          // Route adapter stderr to OUTPUT panel so user can see errors
          _output += '[adapter] $line\n';
          notifyListeners();
        },
      );
      _eventSub = _client!.events.listen(_onEvent);

      // Standard DAP handshake:
      // 1. initialize → adapter responds + fires 'initialized' event
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
      }).timeout(const Duration(seconds: 10));
      // _onInitialized() handles steps 2-4 when 'initialized' event arrives.
    } catch (e) {
      _error = e.toString();
      debugPrint('[DAP] startSession error: $e');
      await _cleanup();
    }
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
      _client = DapStdioClient();
      await _client!.startRemote(remoteStdout, remoteStdin, onStderr: (line) {
        _output += '[adapter] $line\n';
        notifyListeners();
      });
      _eventSub = _client!.events.listen(_onEvent);

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
      }).timeout(const Duration(seconds: 10));
    } catch (e) {
      _error = e.toString();
      debugPrint('[DAP SSH] startSessionRemote error: $e');
      await _cleanup();
    }
  }

  Future<void> stopSession() async {
    if (_status == DebugStatus.idle) return;
    _status = DebugStatus.terminating;
    notifyListeners();
    try {
      await _client?.sendRequest('disconnect', {'terminateDebuggee': true})
          .timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _cleanup();
  }

  Future<void> _cleanup() async {
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
      final program = _dapConfig.launchProgram.isNotEmpty
          ? _dapConfig.launchProgram
          : 'lib/main.dart';
      final deviceId = _dapConfig.deviceIdFor(_platformArg);

      _output += 'Launching $program on $deviceId...\n';
      notifyListeners();

      final launchArgs = <String, dynamic>{
        'program': program,
        'cwd': _projectPath,
        'debugSdkLibraries': false,
        'debugExternalPackageLibraries': false,
        'noDebug': false,
      };

      if (_dapConfig.webPlatform.isNotEmpty && _platformArg == _dapConfig.webPlatform) {
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
    if (_client == null || !isActive) return;
    await _client!.sendRequest('restart');
  }

  Future<void> hotReload() async {
    if (_client == null || !isRunning) return;
    try {
      await _client!.sendRequest('hotReload', {});
    } catch (e) {
      debugPrint('[DAP] hotReload error: $e');
    }
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
    notifyListeners();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _client?.dispose();
    super.dispose();
  }
}
