import 'dart:io';

class FileNode {
  final String name;
  final String path;
  final bool isDirectory;
  bool isExpanded;
  List<FileNode> children;

  FileNode({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.isExpanded = false,
    this.children = const [],
  });

  static Future<FileNode> fromPath(String dirPath) async {
    final name = dirPath.split('/').last.split('\\').last;
    final node = FileNode(
      name: name,
      path: dirPath,
      isDirectory: true,
      isExpanded: true,
    );
    node.children = await _loadChildren(dirPath);
    return node;
  }

  static Future<List<FileNode>> _loadChildren(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final entities = await dir
        .list(followLinks: false)
        .where((e) => !_shouldHide(e.path.split('/').last.split('\\').last))
        .toList();

    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return a.path.compareTo(b.path);
    });

    return entities.map((e) {
      final eName = e.path.split('/').last.split('\\').last;
      return FileNode(
        name: eName,
        path: e.path,
        isDirectory: e is Directory,
      );
    }).toList();
  }

  static bool _shouldHide(String name) {
    const hidden = {'.git', '.dart_tool', 'build', '.gradle', 'node_modules', '__pycache__'};
    return hidden.contains(name);
  }

  Future<void> loadChildren() async {
    if (!isDirectory) return;
    children = await _loadChildren(path);
  }

  String get extension {
    if (isDirectory) return '';
    final dot = name.lastIndexOf('.');
    return dot == -1 ? '' : name.substring(dot + 1);
  }
}
