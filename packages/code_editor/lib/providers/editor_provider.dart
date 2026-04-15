import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:quill_code/quill_code.dart';

/// [QuillCodeController] subclass that fires [onDiagnosticsReceived] the first
/// time the LSP pushes a diagnostics notification. The callback is called once
/// and cleared so it doesn't accumulate closures.
class LspAwareController extends QuillCodeController {
  /// Fires once the first time the LSP pushes a diagnostics notification.
  VoidCallback? onDiagnosticsReceived;

  /// Fires on every [setDiagnostics] call — used to keep the persistent cache
  /// in [EditorProvider] up to date even after a file is closed.
  void Function(List<DiagnosticRegion> regions)? onDiagnosticsChanged;

  LspAwareController({required super.text, super.language});

  @override
  void setDiagnostics(List<DiagnosticRegion> regions) {
    super.setDiagnostics(regions);
    onDiagnosticsChanged?.call(regions);
    final cb = onDiagnosticsReceived;
    if (cb != null) {
      onDiagnosticsReceived = null; // fire once
      cb();
    }
  }
}

class OpenFile {
  final String path;
  final String name;
  bool isDirty;
  bool inBottomPanel;
  QuillCodeController? controller;

  OpenFile({
    required this.path,
    required this.name,
    this.isDirty = false,
    this.inBottomPanel = false,
  });

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1);
  }

  static const _imageExts = {
    'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg',
  };

  /// True when this file should be shown as an image preview (no text editor).
  bool get isImage => _imageExts.contains(extension.toLowerCase());
}

class EditorProvider extends ChangeNotifier {
  final List<OpenFile> _openFiles = [];
  int _activeIndex = -1;
  int _lastTopIdx = -1;
  int _lastBottomIdx = -1;
  FileNode? _rootNode;
  int _treeVersion = 0;

  /// Persistent cache of diagnostics keyed by file path.
  /// Updated whenever [setDiagnostics] is called on any open controller, so
  /// diagnostics are retained even after the file tab is closed.
  final Map<String, List<DiagnosticRegion>> _diagnosticsCache = {};

  Map<String, List<DiagnosticRegion>> get diagnosticsCache =>
      Map.unmodifiable(_diagnosticsCache);

  void _updateDiagnosticsCache(String filePath, List<DiagnosticRegion> regions) {
    if (regions.isEmpty) {
      _diagnosticsCache.remove(filePath);
    } else {
      _diagnosticsCache[filePath] = List.unmodifiable(regions);
    }
    notifyListeners();
  }
  /// Path of the most recently saved file. Updated on every saveActiveFile call.
  String? lastSavedPath;
  /// Set when the project lives on a remote machine; used for tree expand/refresh.
  Future<List<Map<String, dynamic>>> Function(String path)? _remoteListDir;
  /// SFTP read callback — set for remote projects; null for local.
  Future<String> Function(String path)? _remoteReadFile;
  /// SFTP write callback — set for remote projects; null for local.
  Future<void> Function(String path, String content)? _remoteWriteFile;

  List<OpenFile> get openFiles => List.unmodifiable(_openFiles);
  List<OpenFile> get topFiles =>
      List.unmodifiable(_openFiles.where((f) => !f.inBottomPanel));
  List<OpenFile> get bottomPanelFiles =>
      List.unmodifiable(_openFiles.where((f) => f.inBottomPanel));
  int get activeIndex => _activeIndex;
  OpenFile? get activeFile =>
      _activeIndex >= 0 && _activeIndex < _openFiles.length
          ? _openFiles[_activeIndex]
          : null;

  /// The last-active file in the top (main) panel.
  OpenFile? get topActiveFile {
    if (_lastTopIdx >= 0 && _lastTopIdx < _openFiles.length &&
        !_openFiles[_lastTopIdx].inBottomPanel) {
      return _openFiles[_lastTopIdx];
    }
    final i = _openFiles.indexWhere((f) => !f.inBottomPanel);
    return i >= 0 ? _openFiles[i] : null;
  }

  /// The last-active file in the bottom panel.
  OpenFile? get bottomActiveFile {
    if (_lastBottomIdx >= 0 && _lastBottomIdx < _openFiles.length &&
        _openFiles[_lastBottomIdx].inBottomPanel) {
      return _openFiles[_lastBottomIdx];
    }
    final i = _openFiles.indexWhere((f) => f.inBottomPanel);
    return i >= 0 ? _openFiles[i] : null;
  }
  FileNode? get rootNode => _rootNode;
  int get treeVersion => _treeVersion;
  bool get isRemote => _remoteListDir != null;

  Future<void> loadProject(String projectPath) async {
    _remoteListDir = null;
    _remoteReadFile = null;
    _remoteWriteFile = null;
    _rootNode = await FileNode.fromPath(projectPath);
    notifyListeners();
  }

  /// Load a remote project's file tree via an SFTP listing callback.
  /// Pass [readFile] and [writeFile] to enable opening and saving remote files.
  Future<void> loadProjectRemote(
    String projectPath,
    Future<List<Map<String, dynamic>>> Function(String path) listDir, {
    Future<String> Function(String path)? readFile,
    Future<void> Function(String path, String content)? writeFile,
  }) async {
    _remoteListDir = listDir;
    _remoteReadFile = readFile;
    _remoteWriteFile = writeFile;
    _rootNode = await FileNode.fromRemote(projectPath, listDir);
    notifyListeners();
  }

  Future<void> openFile(String filePath, {bool bringToFront = false}) async {
    final existing = _openFiles.indexWhere((f) => f.path == filePath);
    if (existing != -1) {
      // If bringToFront is requested and the file is in the top panel,
      // move it to the first position among top-panel files.
      if (bringToFront && !_openFiles[existing].inBottomPanel) {
        final file = _openFiles[existing];
        final firstTopIdx = _openFiles.indexWhere((f) => !f.inBottomPanel);
        if (existing != firstTopIdx && firstTopIdx >= 0) {
          _openFiles.removeAt(existing);
          _openFiles.insert(firstTopIdx, file);
          _activeIndex = firstTopIdx;
          _lastTopIdx = firstTopIdx;
          notifyListeners();
          return;
        }
      }
      _activeIndex = existing;
      // Also update the per-panel tracking index so EditorArea (which drives
      // its display from topActiveFile / bottomActiveFile, not _activeIndex)
      // actually switches to this file.
      if (_openFiles[existing].inBottomPanel) {
        _lastBottomIdx = existing;
      } else {
        _lastTopIdx = existing;
      }
      notifyListeners();
      return;
    }

    final name = filePath.split('/').last.split('\\').last;
    final openFile = OpenFile(path: filePath, name: name);

    // Image files: no text controller needed — editor_area shows a viewer.
    if (openFile.isImage) {
      _openFiles.add(openFile);
      _activeIndex = _openFiles.length - 1;
      _lastTopIdx  = _activeIndex;
      notifyListeners();
      return;
    }

    String content;
    if (_remoteReadFile != null) {
      try {
        content = await _remoteReadFile!(filePath);
      } catch (_) {
        return; // File not readable over SFTP
      }
    } else {
      final file = File(filePath);
      if (!await file.exists()) return;
      try {
        content = await file.readAsString();
      } catch (_) {
        return; // Binary file or unreadable encoding — skip opening
      }
    }

    final ctrl = LspAwareController(
      text: content,
      language: _detectLanguage(openFile.extension),
    );
    ctrl.onDiagnosticsChanged =
        (regions) => _updateDiagnosticsCache(filePath, regions);
    // Restore any cached diagnostics so the gutter shows immediately on reopen.
    final cached = _diagnosticsCache[filePath];
    if (cached != null && cached.isNotEmpty) {
      ctrl.setDiagnostics(cached);
    }
    openFile.controller = ctrl;

    _openFiles.add(openFile);
    _activeIndex = _openFiles.length - 1;
    if (openFile.inBottomPanel) {
      _lastBottomIdx = _activeIndex;
    } else {
      _lastTopIdx = _activeIndex;
    }
    notifyListeners();
  }

  /// Saves the active file.
  /// If [format] is true and the file is a .dart file, runs
  /// `dart format --output show` and applies the formatted output.
  /// For remote files, uses the SFTP write callback (no dart format).
  Future<void> saveActiveFile({bool format = false}) async {
    final f = activeFile;
    if (f == null || f.controller == null) return;

    String content = f.controller!.content.fullText;

    if (_remoteWriteFile != null) {
      try { await _remoteWriteFile!(f.path, content); } catch (_) {}
      f.isDirty = false;
      lastSavedPath = f.path;
      notifyListeners();
      return;
    }

    if (format && f.extension == 'dart') {
      try {
        // Write first so dart format can read the file.
        await File(f.path).writeAsString(content);
        final dart = '${RuntimeEnvir.usrPath}/bin/dart';
        await Process.run(
          dart,
          ['format', f.path],
          environment: RuntimeEnvir.baseEnv,
        );
        // Read back the (possibly) formatted content.
        content = await File(f.path).readAsString();
      } catch (_) {
        // Formatting failed — save unformatted anyway.
      }
    }

    await File(f.path).writeAsString(content);
    f.isDirty = false;
    lastSavedPath = f.path;
    notifyListeners();
  }

  /// Saves all open files, optionally formatting .dart files.
  /// For remote files, uses the SFTP write callback (no dart format).
  Future<void> saveAllFiles({bool format = false}) async {
    for (var i = 0; i < _openFiles.length; i++) {
      final f = _openFiles[i];
      if (f.controller == null) continue;
      String content = f.controller!.content.fullText;

      if (_remoteWriteFile != null) {
        try { await _remoteWriteFile!(f.path, content); } catch (_) {}
        f.isDirty = false;
        continue;
      }

      if (format && f.extension == 'dart') {
        try {
          await File(f.path).writeAsString(content);
          final dart = '${RuntimeEnvir.usrPath}/bin/dart';
          await Process.run(
            dart,
            ['format', f.path],
            environment: RuntimeEnvir.baseEnv,
          );
          content = await File(f.path).readAsString();
        } catch (_) {}
      }
      await File(f.path).writeAsString(content);
      f.isDirty = false;
    }
    notifyListeners();
  }

  void markDirty() {
    if (activeFile != null && !activeFile!.isDirty) {
      // Only notify on the clean→dirty transition.
      // Subsequent keystrokes (file already dirty) skip the rebuild storm.
      activeFile!.isDirty = true;
      notifyListeners();
    }
  }

  void switchTo(int index) {
    if (index < 0 || index >= _openFiles.length) return;
    _activeIndex = index;
    if (_openFiles[index].inBottomPanel) {
      _lastBottomIdx = index;
    } else {
      _lastTopIdx = index;
    }
    notifyListeners();
  }

  void closeFile(int index) {
    if (index < 0 || index >= _openFiles.length) return;
    // Send didClose so the LSP server frees its per-document state.
    _openFiles[index].controller?.detachLsp();
    _openFiles.removeAt(index);
    if (_activeIndex >= _openFiles.length) {
      _activeIndex = _openFiles.isEmpty ? -1 : _openFiles.length - 1;
    }
    if (_lastTopIdx >= index) _lastTopIdx--;
    if (_lastBottomIdx >= index) _lastBottomIdx--;
    notifyListeners();
  }

  void closeOthers(int index) {
    if (index < 0 || index >= _openFiles.length) return;
    final keep = _openFiles[index];
    for (final f in _openFiles) {
      if (f != keep) f.controller?.detachLsp();
    }
    _openFiles.clear();
    _openFiles.add(keep);
    _activeIndex = 0;
    notifyListeners();
  }

  void closeAll() {
    for (final f in _openFiles) {
      f.controller?.detachLsp();
    }
    _openFiles.clear();
    _activeIndex = -1;
    notifyListeners();
  }

  void reorderFile(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) newIndex -= 1;
    final file = _openFiles.removeAt(oldIndex);
    _openFiles.insert(newIndex, file);
    if (_activeIndex == oldIndex) {
      _activeIndex = newIndex;
    } else if (_activeIndex > oldIndex && _activeIndex <= newIndex) {
      _activeIndex--;
    } else if (_activeIndex < oldIndex && _activeIndex >= newIndex) {
      _activeIndex++;
    }
    notifyListeners();
  }

  bool get canUndo => activeFile?.controller?.content.canUndo ?? false;
  bool get canRedo => activeFile?.controller?.content.canRedo ?? false;

  void undo() {
    activeFile?.controller?.undo();
    notifyListeners();
  }

  void redo() {
    activeFile?.controller?.redo();
    notifyListeners();
  }

  /// Moves a file between top/bottom panels.
  /// When [bottom] is true and [atFirst] is true, inserts the file at
  /// position 0 among bottom-panel files so the new tab appears first.
  void moveToPanel(int globalIndex, {required bool bottom, bool atFirst = false}) {
    if (globalIndex < 0 || globalIndex >= _openFiles.length) return;
    final file = _openFiles[globalIndex];
    file.inBottomPanel = bottom;

    if (bottom && atFirst) {
      _openFiles.removeAt(globalIndex);
      final firstBottom = _openFiles.indexWhere((f) => f.inBottomPanel);
      if (firstBottom == -1) {
        _openFiles.add(file);
      } else {
        _openFiles.insert(firstBottom, file);
      }
      _activeIndex = _openFiles.indexOf(file);
    }
    // Update panel tracking after move
    final newIdx = _openFiles.indexOf(file);
    if (newIdx >= 0) {
      if (bottom) {
        _lastBottomIdx = newIdx;
      } else {
        _lastTopIdx = newIdx;
      }
    }
    notifyListeners();
  }

  Future<void> refreshTree() async {
    if (_rootNode == null) return;
    if (_remoteListDir != null) {
      _rootNode = await FileNode.fromRemote(_rootNode!.path, _remoteListDir!);
    } else {
      _rootNode = await FileNode.fromPath(_rootNode!.path);
    }
    notifyListeners();
  }

  /// Closes [filePath] from the editor if it is currently open so that when
  /// the user reopens it the fresh content from disk is loaded.
  /// Called after the AI agent writes a file.
  void reloadFile(String filePath) {
    final idx = _openFiles.indexWhere((f) => f.path == filePath);
    if (idx < 0) return;
    _openFiles.removeAt(idx);
    if (_activeIndex >= _openFiles.length) {
      _activeIndex = _openFiles.isEmpty ? -1 : _openFiles.length - 1;
    }
    if (_lastTopIdx >= idx) _lastTopIdx = _lastTopIdx > 0 ? _lastTopIdx - 1 : -1;
    if (_lastBottomIdx >= idx) _lastBottomIdx = _lastBottomIdx > 0 ? _lastBottomIdx - 1 : -1;
    notifyListeners();
  }

  void closeFilesUnderPath(String dirPath) {
    _openFiles.removeWhere((f) => f.path.startsWith(dirPath));
    if (_activeIndex >= _openFiles.length) {
      _activeIndex = _openFiles.isEmpty ? -1 : _openFiles.length - 1;
    }
    notifyListeners();
  }

  Future<void> expandNode(FileNode node) async {
    if (!node.isDirectory) return;
    if (_remoteListDir != null) {
      if (!node.isExpanded) await node.loadRemoteChildren(_remoteListDir!);
    } else {
      await node.loadChildren();
    }
    node.isExpanded = !node.isExpanded;
    _treeVersion++;
    notifyListeners();
  }

  static QuillLanguage _detectLanguage(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':
        return DartLanguage();
      case 'js':
      case 'jsx':
      case 'mjs':
      case 'ts':
      case 'tsx':
        return JavaScriptLanguage();
      case 'py':
        return PythonLanguage();
      case 'json':
        return JsonLanguage();
      case 'html':
        return HtmlLanguage();
      case 'css':
        return CssLanguage();
      case 'yaml':
      case 'yml':
        return YamlLanguage();
      case 'kt':
      case 'kts':
        return KotlinLanguage();
      case 'xml':
        return XmlLanguage();
      case 'sh':
      case 'bash':
        return BashLanguage();
      default:
        return PlainTextLanguage();
    }
  }
}
