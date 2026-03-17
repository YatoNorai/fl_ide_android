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
  void startForExtension(String extension, String projectPath) {
    final cmd = _lspServerCommand(extension);
    if (cmd == null) {
      _status = LspStatus.stopped;
      _lspConfig = null;
      notifyListeners();
      return;
    }

    _status = LspStatus.starting;
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

  /// Returns [executable, ...args] for the LSP server, or null if unsupported
  List<String>? _lspServerCommand(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':
        return ['${RuntimeEnvir.flutterPath}/bin/dart', 'language-server'];
      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        return [
          '${RuntimeEnvir.usrPath}/bin/typescript-language-server',
          '--stdio',
        ];
      case 'py':
        return ['${RuntimeEnvir.usrPath}/bin/pylsp'];
      case 'kt':
        return ['${RuntimeEnvir.usrPath}/bin/kotlin-language-server'];
      default:
        return null;
    }
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
