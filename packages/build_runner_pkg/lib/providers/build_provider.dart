import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';

// ── Build platform ────────────────────────────────────────────────────────────

enum BuildPlatform {
  android,
  web,
  linux,
  apk, // generic APK (non-Flutter Android)
  script; // run a script / interpret

  String get label {
    switch (this) {
      case BuildPlatform.android:
        return 'Android';
      case BuildPlatform.web:
        return 'Web';
      case BuildPlatform.linux:
        return 'Linux';
      case BuildPlatform.apk:
        return 'Android APK';
      case BuildPlatform.script:
        return 'Run';
    }
  }

  String get icon {
    switch (this) {
      case BuildPlatform.android:
      case BuildPlatform.apk:
        return '🤖';
      case BuildPlatform.web:
        return '🌐';
      case BuildPlatform.linux:
        return '🐧';
      case BuildPlatform.script:
        return '▶';
    }
  }
}

List<BuildPlatform> supportedPlatforms(SdkType sdk) {
  switch (sdk) {
    case SdkType.flutter:
      return [BuildPlatform.android, BuildPlatform.web, BuildPlatform.linux];
    case SdkType.androidSdk:
      return [BuildPlatform.apk];
    case SdkType.reactNative:
      return [BuildPlatform.android];
    case SdkType.nodejs:
    case SdkType.python:
    case SdkType.swift:
    case SdkType.go:
    case SdkType.kotlinMultiplatform:
    case SdkType.cpp:
    case SdkType.rust:
    case SdkType.lua:
    case SdkType.ruby:
    case SdkType.php:
    case SdkType.bash:
    case SdkType.htmlCss:
    case SdkType.csharp:
    case SdkType.scala:
    case SdkType.r:
    case SdkType.zig:
    case SdkType.haskell:
    case SdkType.elixir:
      return [BuildPlatform.script];
  }
}

// ── BuildProvider ─────────────────────────────────────────────────────────────

class BuildProvider extends ChangeNotifier {
  BuildResult _result = const BuildResult();
  Process? _buildProcess;
  Process? _syncProcess;
  BuildPlatform? _selectedPlatform;
  bool _isSyncing = false;

  // Debounce timer — prevents hundreds of widget rebuilds per second during
  // heavy Gradle output bursts.
  Timer? _notifyTimer;
  bool _pendingNotify = false;

  BuildProvider() {
    MemoryPressureService.instance.addCriticalListener(_onMemoryPressure);
  }

  void _scheduleNotify() {
    _pendingNotify = true;
    _notifyTimer ??= Timer(const Duration(milliseconds: 80), () {
      _notifyTimer = null;
      if (_pendingNotify) {
        _pendingNotify = false;
        notifyListeners();
      }
    });
  }

  // ── Capped log buffers ────────────────────────────────────────────────────
  // Both build/manual and sync outputs are stored as circular queues so that
  // memory stays bounded even for 50 k-line Flutter release builds.
  // 4 000 lines ≈ 300–400 KB worst case — safe on a 4 GB device.
  static const _maxLines = 4000;

  /// Queue for the main build / manual-build session.
  final Queue<String> _buildLines = Queue<String>();

  /// Queue for the sync session (separate so both can coexist).
  final Queue<String> _syncLines = Queue<String>();

  void _appendToQueue(Queue<String> queue, String data) {
    for (final line in data.split('\n')) {
      queue.addLast(line);
      if (queue.length > _maxLines) queue.removeFirst();
    }
  }

  String _queueToString(Queue<String> queue) => queue.join('\n');

  // Cached APK path — recomputed only when a new APK marker line arrives,
  // not on every stdout chunk.
  String? _cachedApkPath;

  BuildResult get result => _result;
  bool get isBuilding => _result.isRunning;
  bool get isSyncing => _isSyncing;
  String? get apkPath => _result.apkPath;

  BuildPlatform selectedPlatform(SdkType sdk) =>
      _selectedPlatform ?? supportedPlatforms(sdk).first;

  void selectPlatform(BuildPlatform p) {
    _selectedPlatform = p;
    notifyListeners();
  }

  Future<void> build(Project project) async {
    if (_result.isRunning) return;

    _buildProcess?.kill();
    _cachedApkPath = null;
    _buildLines.clear();
    _result = const BuildResult(status: BuildStatus.running, output: '');
    notifyListeners();

    try {
      final platform = selectedPlatform(project.sdk);
      final cmd = _buildCommand(project.sdk, platform);

      _buildProcess = await Process.start(
        RuntimeEnvir.bashPath,
        ['-c', cmd],
        workingDirectory: project.path,
        environment: RuntimeEnvir.baseEnv,
      );

      void appendOutput(String data) {
        _appendToQueue(_buildLines, data);
        // Only scan for APK path when output contains the relevant marker.
        if (_cachedApkPath == null &&
            (data.contains('.apk') || data.contains('Built '))) {
          _cachedApkPath = _detectApkPath(data, project.path);
        }
        final fullOutput = _queueToString(_buildLines);
        var newResult = _result.copyWith(
          output: fullOutput,
          apkPath: _cachedApkPath ?? _result.apkPath,
        );
        if (_isSuccess(fullOutput)) {
          newResult = newResult.copyWith(
              status: BuildStatus.success, finishedAt: DateTime.now());
        } else if (_isError(fullOutput)) {
          newResult = newResult.copyWith(
              status: BuildStatus.error, finishedAt: DateTime.now());
        }
        _result = newResult;
        _scheduleNotify();
      }

      _buildProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(appendOutput);
      _buildProcess!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(appendOutput);

      final exitCode = await _buildProcess!.exitCode;
      _notifyTimer?.cancel();
      _notifyTimer = null;
      if (_result.isRunning) {
        _result = _result.copyWith(
          status: exitCode == 0 ? BuildStatus.success : BuildStatus.error,
          finishedAt: DateTime.now(),
        );
        notifyListeners();
      }
    } catch (e) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _result = _result.copyWith(
        status: BuildStatus.error,
        output: '${_result.output}\nError: $e',
        finishedAt: DateTime.now(),
      );
      notifyListeners();
    }
  }

  void cancel() {
    _buildProcess?.kill();
    _appendToQueue(_buildLines, '\n[Build cancelled]');
    _result = _result.copyWith(
      status: BuildStatus.error,
      output: _queueToString(_buildLines),
    );
    notifyListeners();
  }

  void reset() {
    _result = const BuildResult();
    notifyListeners();
  }

  // ── Manual build (used by remote git build) ────────────────────────────────

  /// Starts a manually-controlled build session (e.g. remote GitHub Actions).
  void startManual() {
    if (_result.isRunning) return;
    _cachedApkPath = null;
    _buildLines.clear();
    _result = const BuildResult(status: BuildStatus.running, output: '');
    notifyListeners();
  }

  /// Appends a line of output to the current manual build result.
  void appendManualOutput(String data) {
    if (!_result.isRunning) return;
    _appendToQueue(_buildLines, data);
    _result = _result.copyWith(output: _queueToString(_buildLines));
    _scheduleNotify();
  }

  /// Finishes a manually-controlled build session.
  void finishManual({required bool success, String? apkPath}) {
    _notifyTimer?.cancel();
    _notifyTimer = null;
    _result = _result.copyWith(
      status: success ? BuildStatus.success : BuildStatus.error,
      apkPath: apkPath,
      finishedAt: DateTime.now(),
    );
    notifyListeners();
  }

  /// Runs [command] in [workingDir] as a background process and streams
  /// stdout + stderr to the OUTPUT tab (via [result.output]).
  /// Separate from [build] so build state is not disturbed.
  Future<void> sync(String command, String workingDir) async {
    if (_isSyncing) return;
    _isSyncing = true;
    _syncLines.clear();
    _appendToQueue(_syncLines, '> $command\n');
    _result = BuildResult(
      status: BuildStatus.running,
      output: _queueToString(_syncLines),
    );
    notifyListeners();

    try {
      _syncProcess = await Process.start(
        RuntimeEnvir.bashPath,
        ['-c', command],
        workingDirectory: workingDir,
        environment: RuntimeEnvir.baseEnv,
      );

      void appendOutput(String data) {
        _appendToQueue(_syncLines, data);
        _result = _result.copyWith(output: _queueToString(_syncLines));
        _scheduleNotify();
      }

      _syncProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(appendOutput);
      _syncProcess!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(appendOutput);

      final code = await _syncProcess!.exitCode;
      _notifyTimer?.cancel();
      _notifyTimer = null;
      final done = code == 0 ? '\n\u2714 Done\n' : '\n\u2716 Exited with code $code\n';
      _appendToQueue(_syncLines, done);
      _result = _result.copyWith(
        status: code == 0 ? BuildStatus.success : BuildStatus.error,
        output: _queueToString(_syncLines),
        finishedAt: DateTime.now(),
      );
    } catch (e) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _appendToQueue(_syncLines, '\nError: $e\n');
      _result = _result.copyWith(
        status: BuildStatus.error,
        output: _queueToString(_syncLines),
        finishedAt: DateTime.now(),
      );
    }

    _isSyncing = false;
    _syncProcess = null;
    notifyListeners();
  }

  void cancelSync() {
    _syncProcess?.kill();
    _syncProcess = null;
    _isSyncing = false;
    _appendToQueue(_syncLines, '\n[Sync cancelled]\n');
    _result = _result.copyWith(
      status: BuildStatus.error,
      output: _queueToString(_syncLines),
    );
    notifyListeners();
  }

  // Gradle flags that speed up every build significantly:
  //   --parallel           — build subprojects concurrently
  //   --build-cache        — reuse outputs from prior builds
  //   --configure-on-demand — skip configuring unused subprojects
  //   -x lint              — skip lint (slow, not needed for debug APK)
  static const _gradleFlags =
      '--parallel --build-cache --configure-on-demand -x lint';

  String _buildCommand(SdkType sdk, BuildPlatform platform) {
    switch (sdk) {
      case SdkType.flutter:
        switch (platform) {
          case BuildPlatform.web:
            return 'flutter build web';
          case BuildPlatform.linux:
            return 'flutter build linux';
          default:
            return 'flutter build apk --debug';
        }
      case SdkType.androidSdk:
        return './gradlew assembleDebug $_gradleFlags';
      case SdkType.reactNative:
        return 'npx react-native build-android --mode=debug';
      case SdkType.nodejs:
        return 'npm run build';
      case SdkType.python:
        return 'python3 main.py';
      case SdkType.swift:
        return 'swift build';
      case SdkType.go:
        return 'go build -o app .';
      case SdkType.kotlinMultiplatform:
        return 'kotlinc . -include-runtime -d app.jar';
      case SdkType.cpp:
        return 'cmake -GNinja . && ninja';
      case SdkType.rust:
        return 'cargo build';
      case SdkType.lua:
        return 'lua main.lua';
      case SdkType.ruby:
        return 'ruby main.rb';
      case SdkType.php:
        return 'php index.php';
      case SdkType.bash:
        return 'bash main.sh';
      case SdkType.htmlCss:
        return 'echo "Open index.html in a browser"';
      case SdkType.csharp:
        return 'dotnet build';
      case SdkType.scala:
        return 'scala-cli compile .';
      case SdkType.r:
        return 'Rscript main.R';
      case SdkType.zig:
        return 'zig build';
      case SdkType.haskell:
        return 'cabal build';
      case SdkType.elixir:
        return 'mix compile';
    }
  }

  String? _detectApkPath(String output, String projectPath) {
    final patterns = [
      RegExp(r'Built (.+\.apk)'),
      RegExp(r'APK.+\.apk'),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(output);
      if (match != null) {
        var path = (match.groupCount >= 1 ? match.group(1) : match.group(0)) ?? '';
        path = path.trim();
        if (!path.startsWith('/')) path = '$projectPath/$path';
        if (File(path).existsSync()) return path;
      }
    }
    final flutterApk =
        '$projectPath/build/app/outputs/flutter-apk/app-debug.apk';
    if (File(flutterApk).existsSync()) return flutterApk;
    return null;
  }

  bool _isSuccess(String output) =>
      output.contains('BUILD SUCCESSFUL') ||
      output.contains('✓ Built') ||
      output.contains('Gradle build done');

  bool _isError(String output) =>
      output.contains('BUILD FAILED') ||
      (output.contains('Error:') && output.contains('Exception:'));

  /// Invoked by [MemoryPressureService] when Android signals critical memory
  /// pressure (TRIM_MEMORY_MODERATE / TRIM_MEMORY_COMPLETE / onLowMemory).
  /// Truncates both log queues to the most recent 500 lines to free memory
  /// while keeping enough context to be useful.
  void _onMemoryPressure() {
    const keepLines = 500;
    bool changed = false;
    while (_buildLines.length > keepLines) {
      _buildLines.removeFirst();
      changed = true;
    }
    while (_syncLines.length > keepLines) {
      _syncLines.removeFirst();
      changed = true;
    }
    if (changed) {
      _result = _result.copyWith(output: _queueToString(_buildLines));
      notifyListeners();
    }
  }

  @override
  void dispose() {
    MemoryPressureService.instance.removeCriticalListener(_onMemoryPressure);
    _notifyTimer?.cancel();
    _buildProcess?.kill();
    _syncProcess?.kill();
    super.dispose();
  }
}
