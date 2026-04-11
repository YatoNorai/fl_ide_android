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
  BuildPlatform? _selectedPlatform;

  BuildResult get result => _result;
  bool get isBuilding => _result.isRunning;
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
    _result = const BuildResult(status: BuildStatus.running, output: '');
    notifyListeners();

    try {
      final platform = selectedPlatform(project.sdk);
      final cmd = _buildCommand(project.sdk, platform);
      final parts = cmd.split(' ');

      _buildProcess = await Process.start(
        parts.first,
        parts.sublist(1),
        workingDirectory: project.path,
        environment: RuntimeEnvir.baseEnv,
        runInShell: true,
      );

      final outputBuffer = StringBuffer();

      void appendOutput(String data) {
        outputBuffer.write(data);
        final apk = _detectApkPath(data, project.path);
        var newResult = _result.copyWith(output: outputBuffer.toString());
        if (apk != null) newResult = newResult.copyWith(apkPath: apk);
        if (_isSuccess(outputBuffer.toString())) {
          newResult = newResult.copyWith(
              status: BuildStatus.success, finishedAt: DateTime.now());
        } else if (_isError(outputBuffer.toString())) {
          newResult = newResult.copyWith(
              status: BuildStatus.error, finishedAt: DateTime.now());
        }
        _result = newResult;
        notifyListeners();
      }

      _buildProcess!.stdout
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(appendOutput);
      _buildProcess!.stderr
          .transform(const Utf8Decoder(allowMalformed: true))
          .listen(appendOutput);

      final exitCode = await _buildProcess!.exitCode;
      if (_result.isRunning) {
        _result = _result.copyWith(
          status: exitCode == 0 ? BuildStatus.success : BuildStatus.error,
          finishedAt: DateTime.now(),
        );
        notifyListeners();
      }
    } catch (e) {
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
        return './gradlew assembleDebug';
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
    _buildProcess?.kill();
    super.dispose();
  }
}
