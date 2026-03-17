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

  // Bootstrap URL — ARM64 package (same approach as termare)
  static const String _bootstrapUrl =
      'https://github.com/termux/termux-packages/releases/download/bootstrap-2024.01.01/bootstrap-aarch64.zip';

  void checkBootstrap() {
    _state = RootfsState.checking;
    notifyListeners();

    if (RuntimeEnvir.isBootstrapped) {
      _state = RootfsState.ready;
      _statusMessage = 'RootFS ready';
    } else {
      _state = RootfsState.notInstalled;
      _statusMessage = 'RootFS not installed';
    }
    notifyListeners();
  }

  Future<void> downloadAndInstall() async {
    try {
      // Step 1: Create directories
      _setState(RootfsState.downloading, 'Preparing directories...', 0.0);
      await _createDirectories();

      // Step 2: Download bootstrap
      _setState(RootfsState.downloading, 'Downloading bootstrap...', 0.05);
      final zipBytes = await _downloadBootstrap();

      // Step 3: Extract
      _setState(RootfsState.extracting, 'Extracting files...', 0.7);
      await _extractBootstrap(zipBytes);

      // Step 4: Run init script
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

  Future<Uint8List> _downloadBootstrap() async {
    final dio = Dio();
    final response = await dio.get<ResponseBody>(
      _bootstrapUrl,
      options: Options(responseType: ResponseType.stream),
    );

    final contentLength =
        int.tryParse(response.headers.value('content-length') ?? '') ?? 0;
    final bytes = <int>[];

    await for (final chunk in response.data!.stream) {
      bytes.addAll(chunk);
      if (contentLength > 0) {
        final dl = 0.05 + (bytes.length / contentLength) * 0.6;
        _setState(RootfsState.downloading,
            'Downloading... ${(bytes.length / 1024 / 1024).toStringAsFixed(1)} MB',
            dl.clamp(0.05, 0.65));
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
      } else {
        await Directory(filePath).create(recursive: true);
      }

      done++;
      final p = 0.7 + (done / total) * 0.18;
      _setState(RootfsState.extracting,
          'Extracting... $done/$total', p.clamp(0.7, 0.88));
    }
  }

  Future<void> _runInitScript() async {
    // Create symlinks from SYMLINKS.txt if present
    final symlinksFile =
        File('${RuntimeEnvir.usrPath}/SYMLINKS.txt');
    if (await symlinksFile.exists()) {
      final lines = await symlinksFile.readAsLines();
      for (final line in lines) {
        final parts = line.split('←');
        if (parts.length == 2) {
          final target = parts[0].trim();
          final linkPath = '${RuntimeEnvir.usrPath}/${parts[1].trim()}';
          try {
            final link = Link(linkPath);
            if (!await link.exists()) {
              await link.create(target);
            }
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
