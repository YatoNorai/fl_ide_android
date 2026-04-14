import 'dart:async';
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

      final outputBuffer = StringBuffer();

      void appendOutput(String data) {
        outputBuffer.write(data);
        // Only scan for APK path when output contains the relevant marker.
        if (_cachedApkPath == null &&
            (data.contains('.apk') || data.contains('Built '))) {
          _cachedApkPath = _detectApkPath(data, project.path);
        }
        final fullOutput = outputBuffer.toString();
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
    _result = _result.copyWith(
      status: BuildStatus.error,
      output: '${_result.output}\n[Build cancelled]',
    );
    notifyListeners();
  }

  void reset() {
    _result = const BuildResult();
    notifyListeners();
  }

  /// Runs [command] in [workingDir] as a background process and streams
  /// stdout + stderr to the OUTPUT tab (via [result.output]).
  /// Separate from [build] so build state is not disturbed.
  Future<void> sync(String command, String workingDir) async {
    if (_isSyncing) return;
    _isSyncing = true;
    _result = BuildResult(
      status: BuildStatus.running,
      output: '> $command\n',
    );
    notifyListeners();

    try {
      _syncProcess = await Process.start(
        RuntimeEnvir.bashPath,
        ['-c', command],
        workingDirectory: workingDir,
        environment: RuntimeEnvir.baseEnv,
      );

      final buf = StringBuffer(_result.output);

      void appendOutput(String data) {
        buf.write(data);
        _result = _result.copyWith(output: buf.toString());
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
      _result = _result.copyWith(
        status: code == 0 ? BuildStatus.success : BuildStatus.error,
        output: buf.toString() + done,
        finishedAt: DateTime.now(),
      );
    } catch (e) {
      _notifyTimer?.cancel();
      _notifyTimer = null;
      _result = _result.copyWith(
        status: BuildStatus.error,
        output: '${_result.output}\nError: $e\n',
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
    _result = _result.copyWith(
      status: BuildStatus.error,
      output: '${_result.output}\n[Sync cancelled]\n',
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

  @override
  void dispose() {
    _notifyTimer?.cancel();
    _buildProcess?.kill();
    _syncProcess?.kill();
    super.dispose();
  }
}
