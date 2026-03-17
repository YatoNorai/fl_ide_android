import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:quill_code/quill_code.dart';

class OpenFile {
  final String path;
  final String name;
  bool isDirty;
  QuillCodeController? controller;

  OpenFile({required this.path, required this.name, this.isDirty = false});

  String get extension {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1);
  }
}

class EditorProvider extends ChangeNotifier {
  final List<OpenFile> _openFiles = [];
  int _activeIndex = -1;
  FileNode? _rootNode;

  List<OpenFile> get openFiles => List.unmodifiable(_openFiles);
  int get activeIndex => _activeIndex;
  OpenFile? get activeFile =>
      _activeIndex >= 0 && _activeIndex < _openFiles.length
          ? _openFiles[_activeIndex]
          : null;
  FileNode? get rootNode => _rootNode;

  Future<void> loadProject(String projectPath) async {
    _rootNode = await FileNode.fromPath(projectPath);
    notifyListeners();
  }

  Future<void> openFile(String filePath) async {
    final existing = _openFiles.indexWhere((f) => f.path == filePath);
    if (existing != -1) {
      _activeIndex = existing;
      notifyListeners();
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) return;

    final content = await file.readAsString();
    final name = filePath.split('/').last.split('\\').last;
    final openFile = OpenFile(path: filePath, name: name);

    openFile.controller = QuillCodeController(
      text: content,
      language: _detectLanguage(openFile.extension),
    );

    _openFiles.add(openFile);
    _activeIndex = _openFiles.length - 1;
    notifyListeners();
  }

  Future<void> saveActiveFile() async {
    final f = activeFile;
    if (f == null || f.controller == null) return;

    final content = f.controller!.content.fullText;
    await File(f.path).writeAsString(content);
    f.isDirty = false;
    notifyListeners();
  }

  void markDirty() {
    if (activeFile != null) {
      activeFile!.isDirty = true;
      notifyListeners();
    }
  }

  void switchTo(int index) {
    if (index < 0 || index >= _openFiles.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void closeFile(int index) {
    if (index < 0 || index >= _openFiles.length) return;
    _openFiles.removeAt(index);
    if (_activeIndex >= _openFiles.length) {
      _activeIndex = _openFiles.isEmpty ? -1 : _openFiles.length - 1;
    }
    notifyListeners();
  }

  Future<void> expandNode(FileNode node) async {
    if (!node.isDirectory) return;
    await node.loadChildren();
    node.isExpanded = !node.isExpanded;
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
