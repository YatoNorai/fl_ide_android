import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

import '../models/log_line.dart';

export '../models/log_line.dart';

// ── LogcatProvider ────────────────────────────────────────────────────────────
//
// Two independent modes — whichever connects first wins:
//
//   MODE A — Bridge (preferred, no permissions needed):
//     The user's app runs FLIDELogBridge.java (auto-injected by fl_ide).
//     The bridge reads the app's own logcat internally and forwards lines
//     to fl_ide over a local TCP socket on port 8877.
//     fl_ide runs a ServerSocket that accepts the connection.
//
//   MODE B — Direct logcat (fallback, requires READ_LOGS):
//     1. Scan /proc/*/cmdline to find the app PID (no ADB needed).
//     2. Run `logcat --pid=<pid> -v threadtime` directly.
//     Requires: adb shell pm grant com.termux android.permission.READ_LOGS
//
// The socket server (Mode A) always listens once start() is called.
// If a bridge connection arrives before the direct logcat connects, Mode B
// is cancelled and bridge lines are shown instead.

class LogcatProvider extends ChangeNotifier {
  static const int _maxLines    = 5000;
  static const int _trimTarget  = 4700;
  static const int _maxPidWaitS = 90;
  static const int bridgePort   = 8877;

  final List<LogLine> _lines = [];

  // ── Mode A (bridge) ────────────────────────────────────────────────────────
  ServerSocket? _server;
  Socket? _bridgeSocket;
  bool _bridgeConnected = false;

  // ── Mode B (direct logcat) ─────────────────────────────────────────────────
  Process? _process;
  String? _logcatCmd; // probed once: 'logcat' | 'adb logcat' | null

  // ── Common state ───────────────────────────────────────────────────────────
  bool    _running  = false;
  bool    _disposed = false;
  String? _packageName;
  String? _setupError; // set when neither mode works

  // ── Public API ──────────────────────────────────────────────────────────────

  bool          get isRunning      => _running;
  bool          get bridgeConnected => _bridgeConnected;
  List<LogLine> get lines          => _lines;
  String?       get packageName    => _packageName;
  String?       get setupError     => _setupError;

  /// Start watching logs for [packageName].  Safe to call if already running.
  Future<void> start(String packageName) async {
    if (_running && _packageName == packageName) return;
    stop();
    _packageName = packageName;
    _setupError  = null;
    _running     = true;
    notifyListeners();

    // Start the socket server (Mode A) and the direct logcat loop (Mode B)
    // concurrently.  Whichever produces output first is used; the other is
    // cancelled once the bridge connects.
    unawaited(_startSocketServer());
    unawaited(_runDirectLogcat(packageName));
  }

  void stop() {
    _running          = false;
    _bridgeConnected  = false;
    _setupError       = null;
    _process?.kill();
    _process          = null;
    _bridgeSocket?.destroy();
    _bridgeSocket     = null;
    _server?.close();
    _server           = null;
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  // ── Package-name + APK helpers ─────────────────────────────────────────────

  /// Scans build.gradle / AndroidManifest.xml for the app package name.
  static String? detectPackageName(String projectPath) {
    final gradlePaths = [
      '$projectPath/android/app/build.gradle',
      '$projectPath/android/app/build.gradle.kts',
      '$projectPath/app/build.gradle',
      '$projectPath/app/build.gradle.kts',
    ];
    for (final p in gradlePaths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      final m = RegExp('applicationId\\s*[=]?\\s*["\']([a-zA-Z][a-zA-Z0-9_.]+)["\']')
          .firstMatch(f.readAsStringSync());
      if (m != null) return m.group(1);
    }
    final manifestPaths = [
      '$projectPath/app/src/main/AndroidManifest.xml',
      '$projectPath/android/app/src/main/AndroidManifest.xml',
    ];
    for (final p in manifestPaths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      final m = RegExp(r'package="([a-zA-Z][a-zA-Z0-9_.]+)"').firstMatch(f.readAsStringSync());
      if (m != null) return m.group(1);
    }
    return null;
  }

  /// Returns the most recently modified APK across all known output paths.
  static String? findLatestApk(String projectPath) {
    final candidates = [
      '$projectPath/build/app/outputs/flutter-apk/app-debug.apk',
      '$projectPath/build/app/outputs/flutter-apk/app-release.apk',
      '$projectPath/app/build/outputs/apk/debug/app-debug.apk',
      '$projectPath/app/build/outputs/apk/release/app-release.apk',
      '$projectPath/android/app/build/outputs/apk/debug/app-debug.apk',
      '$projectPath/android/app/build/outputs/apk/release/app-release.apk',
    ];
    File? latest;
    for (final p in candidates) {
      final f = File(p);
      if (!f.existsSync()) continue;
      if (latest == null || f.lastModifiedSync().isAfter(latest.lastModifiedSync())) {
        latest = f;
      }
    }
    return latest?.path;
  }

  // ── MODE A — Socket server (bridge) ────────────────────────────────────────

  Future<void> _startSocketServer() async {
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, bridgePort);
      debugPrint('[LogcatProvider] bridge server listening on port $bridgePort');

      await for (final socket in _server!) {
        if (_disposed || !_running) {
          socket.destroy();
          break;
        }
        // Accept the latest connection (only one bridge at a time).
        _bridgeSocket?.destroy();
        _bridgeSocket    = socket;
        _bridgeConnected = true;

        // Cancel the direct logcat process — bridge takes over.
        _process?.kill();
        _process = null;

        _addSystem('─── Bridge connected (FLIDELogBridge) ───');
        notifyListeners();

        await _streamFromSocket(socket);

        if (!_disposed && _running) {
          _bridgeConnected = false;
          _addSystem('─── Bridge disconnected ───');
          notifyListeners();
        }
      }
    } on SocketException catch (e) {
      debugPrint('[LogcatProvider] bridge server error: $e');
    } finally {
      _server = null;
    }
  }

  Future<void> _streamFromSocket(Socket socket) async {
    try {
      await for (final raw in socket
          .cast<List<int>>()
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
        if (_disposed || !_running) break;
        final line = LogLine.parse(raw);
        if (line != null) _addLine(line);
      }
    } catch (e) {
      debugPrint('[LogcatProvider] bridge socket stream error: $e');
    }
  }

  // ── MODE B — Direct logcat (READ_LOGS) ─────────────────────────────────────

  Future<void> _runDirectLogcat(String packageName) async {
    // Give the bridge a 2-second head-start.  If it connects, this loop will
    // see _bridgeConnected == true and skip the direct logcat.
    await Future.delayed(const Duration(seconds: 2));
    if (!_running || _disposed || _bridgeConnected) return;

    // Probe which logcat command works (only once per provider lifetime).
    _logcatCmd ??= await _probeLogcatCommand();
    if (_logcatCmd == null) {
      if (!_bridgeConnected && _running && !_disposed) {
        _setupError =
            'Cannot read logcat directly.\n\n'
            'Option 1 — Inject the Log Bridge into your project '
            '(no permissions needed, tap the bridge button in the toolbar).\n\n'
            'Option 2 — Grant READ_LOGS to Termux once:\n'
            'adb shell pm grant com.termux android.permission.READ_LOGS';
        _running = false;
        notifyListeners();
      }
      return;
    }

    while (!_disposed && _running && !_bridgeConnected) {
      String? pid;
      _addSystem('Waiting for $packageName to start…');

      for (int i = 0; i < _maxPidWaitS && !_disposed && _running && !_bridgeConnected; i++) {
        pid = await _getPid(packageName);
        if (pid != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }

      if (!_running || _disposed || _bridgeConnected) break;

      if (pid == null) {
        _addSystem('Timed out waiting for $packageName.');
        _running = false;
        if (!_disposed) notifyListeners();
        break;
      }

      _addSystem('─── $packageName started (PID $pid) ───');
      await _streamLogcat(pid);

      if (!_running || _disposed || _bridgeConnected) break;
      _addSystem('─── $packageName stopped ───');
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }

  Future<String?> _probeLogcatCommand() async {
    for (final cmd in ['logcat', 'adb logcat']) {
      try {
        final r = await Process.run(
          RuntimeEnvir.bashPath,
          ['-c', '$cmd -d 2>/dev/null | head -5'],
          environment: RuntimeEnvir.baseEnv,
        ).timeout(const Duration(seconds: 4));
        if ((r.stdout as String).trim().isNotEmpty) {
          debugPrint('[LogcatProvider] using: $cmd');
          return cmd;
        }
      } catch (_) {}
    }
    return null;
  }

  // ── PID detection ─────────────────────────────────────────────────────────

  Future<String?> _getPid(String packageName) async {
    return _getPidFromProc(packageName) ?? await _getPidFromAdb(packageName);
  }

  String? _getPidFromProc(String packageName) {
    try {
      for (final entity in Directory('/proc').listSync(followLinks: false)) {
        if (entity is! Directory) continue;
        final pidStr = entity.path.split('/').last;
        if (int.tryParse(pidStr) == null) continue;
        // The process may exit between listSync() and the read — check first
        // to avoid throwing PathNotFoundException in the Flutter debugger.
        final cmdlineFile = File('${entity.path}/cmdline');
        if (!cmdlineFile.existsSync()) continue;
        try {
          final bytes = cmdlineFile.readAsBytesSync();
          if (bytes.isEmpty) continue;
          final nullIdx = bytes.indexOf(0);
          final name = utf8.decode(
            nullIdx >= 0 ? bytes.sublist(0, nullIdx) : bytes,
            allowMalformed: true,
          ).trim();
          if (name == packageName || name.startsWith('$packageName:')) return pidStr;
        } catch (_) {}
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _getPidFromAdb(String packageName) async {
    try {
      final r = await Process.run(
        RuntimeEnvir.bashPath,
        ['-c', 'adb shell pidof "$packageName" 2>/dev/null'],
        environment: RuntimeEnvir.baseEnv,
      ).timeout(const Duration(seconds: 4));
      final out = (r.stdout as String).trim();
      if (out.isEmpty) return null;
      final first = out.split(RegExp(r'\s+')).first.trim();
      return int.tryParse(first) != null ? first : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _streamLogcat(String pid) async {
    final cmd = _logcatCmd;
    if (cmd == null) return;
    try {
      _process = await Process.start(
        RuntimeEnvir.bashPath,
        ['-c', '$cmd --pid=$pid -v threadtime 2>/dev/null'],
        environment: RuntimeEnvir.baseEnv,
      );
      _process!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())
          .listen((l) { if (l.trim().isNotEmpty) debugPrint('[logcat stderr] $l'); });

      await for (final raw in _process!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter())) {
        if (_disposed || !_running || _bridgeConnected) break;
        final line = LogLine.parse(raw);
        if (line != null) _addLine(line);
      }
      await _process?.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -1);
      _process = null;
    } catch (e) {
      debugPrint('[LogcatProvider] stream error: $e');
      _process = null;
    }
  }

  // ── Buffer ─────────────────────────────────────────────────────────────────

  void _addLine(LogLine line) {
    _lines.add(line);
    if (_lines.length >= _maxLines) {
      _lines.removeRange(0, _lines.length - _trimTarget);
    }
    if (!_disposed) notifyListeners();
  }

  void _addSystem(String text) => _addLine(LogLine.system(text));

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _disposed = true;
    _process?.kill();
    _bridgeSocket?.destroy();
    _server?.close();
    super.dispose();
  }
}
