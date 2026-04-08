import 'dart:io';

// Top-level const — single allocation for the lifetime of the app.
const _kHiddenDirs = {
  '.git', '.dart_tool', 'build', '.gradle',
  'node_modules', '__pycache__',
};

/// Extracts the last path component without allocating two intermediate lists.
String _basename(String path) {
  final sep = path.lastIndexOf('/');
  final bsep = path.lastIndexOf('\\');
  final idx = sep > bsep ? sep : bsep;
  return idx < 0 ? path : path.substring(idx + 1);
}

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
    final name = _basename(dirPath);
    final node = FileNode(
      name: name,
      path: dirPath,
      isDirectory: true,
      isExpanded: true,
    );
    node.children = await _loadChildren(dirPath);
    return node;
  }

  /// Build a FileNode tree using a remote listing callback (SFTP).
  /// [listDir] receives a path and returns a list of entry maps with keys:
  ///   'name' (String), 'path' (String), 'isDirectory' (bool)
  static Future<FileNode> fromRemote(
    String dirPath,
    Future<List<Map<String, dynamic>>> Function(String path) listDir,
  ) async {
    final name = _basename(dirPath);
    final node = FileNode(
      name: name,
      path: dirPath,
      isDirectory: true,
      isExpanded: true,
    );
    node.children = await _loadRemoteChildren(dirPath, listDir);
    return node;
  }

  static Future<List<FileNode>> _loadRemoteChildren(
    String dirPath,
    Future<List<Map<String, dynamic>>> Function(String) listDir,
  ) async {
    try {
      final entries = await listDir(dirPath);
      final nodes = entries
          .where((e) => !_shouldHide(e['name'] as String))
          .map((e) => FileNode(
                name: e['name'] as String,
                path: e['path'] as String,
                isDirectory: e['isDirectory'] as bool,
              ))
          .toList();
      nodes.sort((a, b) {
        if (a.isDirectory && !b.isDirectory) return -1;
        if (!a.isDirectory && b.isDirectory) return 1;
        return a.name.compareTo(b.name);
      });
      return nodes;
    } catch (_) {
      return [];
    }
  }

  /// Load children of this node via SFTP callback (lazy expand).
  Future<void> loadRemoteChildren(
    Future<List<Map<String, dynamic>>> Function(String) listDir,
  ) async {
    if (!isDirectory) return;
    children = await _loadRemoteChildren(path, listDir);
  }

  static Future<List<FileNode>> _loadChildren(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final entities = await dir
        .list(followLinks: false)
        .where((e) => !_shouldHide(_basename(e.path)))
        .toList();

    entities.sort((a, b) {
      final aIsDir = a is Directory;
      final bIsDir = b is Directory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return a.path.compareTo(b.path);
    });

    return entities.map((e) => FileNode(
          name: _basename(e.path),
          path: e.path,
          isDirectory: e is Directory,
        )).toList();
  }

  static bool _shouldHide(String name) => _kHiddenDirs.contains(name);

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
