import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:quill_code/quill_code.dart';

enum LspStatus { stopped, starting, running, error }

class LspProvider extends ChangeNotifier {
  LspStatus _status = LspStatus.stopped;
  QuillLspConfig? _lspConfig;
  String? _error;

  LspStatus get status => _status;
  QuillLspConfig? get lspConfig => _lspConfig;
  String? get error => _error;
  bool get isRunning => _status == LspStatus.running;

  /// Build a QuillLspStdioConfig for the given file extension.
  /// The config is passed to QuillCodeEditor which manages the connection.
  /// [customPaths] overrides default binary paths per extension (key = ext, value = binary path).
  Future<void> startForExtension(String extension, String projectPath,
      {Map<String, String>? customPaths}) async {
    final cmd = _lspServerCommand(extension, customPaths: customPaths);
    if (cmd == null) {
      _status = LspStatus.stopped;
      _lspConfig = null;
      notifyListeners();
      return;
    }

    _status = LspStatus.starting;
    notifyListeners();

    // Let the UI render the "starting" state before switching to running.
    await Future.microtask(() {});

    _lspConfig = QuillLspStdioConfig(
      executable: cmd.first,
      args: cmd.sublist(1),
      languageId: _languageId(extension),
      workspacePath: projectPath,
    );
    _status = LspStatus.running;
    notifyListeners();
  }

  void stop() {
    _lspConfig = null;
    _status = LspStatus.stopped;
    notifyListeners();
  }

  /// Returns [executable, ...args] for the LSP server, or null if the binary
  /// is not installed or the extension is unsupported.
  List<String>? _lspServerCommand(String ext,
      {Map<String, String>? customPaths}) {
    // Check user-supplied custom path first
    final customExe = customPaths?[ext.toLowerCase()];
    if (customExe != null && customExe.isNotEmpty) {
      if (!File(customExe).existsSync()) {
        debugPrint('[LspProvider] custom binary not found: $customExe');
        return null;
      }
      // .dart.snapshot files must be run through the Dart VM, not directly.
      if (customExe.endsWith('.dart.snapshot')) {
        final dartVm = _dartVmPath;
        if (dartVm == null) {
          debugPrint('[LspProvider] dart VM not found, cannot run snapshot');
          return null;
        }
        return [dartVm, customExe, '--lsp'];
      }
      return [customExe];
    }

    String? exe;
    List<String> args = [];

    switch (ext.toLowerCase()) {
      case 'dart':
        // Use the dart VM binary directly (not the shell wrapper flutter/bin/dart)
        // so it can be exec'd from Android without a shell interpreter.
        exe = _dartVmPath;
        args = ['language-server'];
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        exe = '${RuntimeEnvir.usrPath}/bin/typescript-language-server';
        args = ['--stdio'];
      case 'py':
        exe = '${RuntimeEnvir.usrPath}/bin/pylsp';
      case 'kt':
        exe = '${RuntimeEnvir.usrPath}/bin/kotlin-language-server';
      default:
        return null;
    }

    if (exe == null || !File(exe).existsSync()) {
      debugPrint('[LspProvider] binary not found, skipping LSP: $exe');
      return null;
    }

    return [exe, ...args];
  }

  /// Path to the Dart VM binary (the ELF executable, not the shell wrapper).
  String? get _dartVmPath {
    final path = '${RuntimeEnvir.flutterPath}/bin/cache/dart-sdk/bin/dart';
    return File(path).existsSync() ? path : null;
  }

  String _languageId(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':   return 'dart';
      case 'js':     return 'javascript';
      case 'jsx':    return 'javascriptreact';
      case 'ts':     return 'typescript';
      case 'tsx':    return 'typescriptreact';
      case 'py':     return 'python';
      case 'kt':     return 'kotlin';
      case 'java':   return 'java';
      default:       return ext;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
