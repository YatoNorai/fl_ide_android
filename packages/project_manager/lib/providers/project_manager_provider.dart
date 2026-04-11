import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../project_template.dart';

class ProjectManagerProvider extends ChangeNotifier {
  final List<Project> _projects = [];
  final List<Project> _remoteProjects = [];
  Project? _activeProject;
  bool _activeProjectIsNew = false;

  List<Project> get projects => List.unmodifiable(_projects);
  List<Project> get remoteProjects => List.unmodifiable(_remoteProjects);
  Project? get activeProject => _activeProject;
  /// True if the active project was just created (not loaded from history).
  bool get activeProjectIsNew => _activeProjectIsNew;

  Future<void> initialize() async {
    await _loadProjects();
    await Directory(RuntimeEnvir.projectsPath).create(recursive: true);
  }

  Future<Project> createProject({
    required String name,
    required SdkType sdk,
    required Future<void> Function(String script) runInTerminal,
    String? newProjectCmd,
    String? projectsBasePath,
    bool remoteIsWindows = false,
    // Android-specific options
    String androidLanguage = 'kotlin',
    int androidMinSdk = 24,
    AndroidTemplate androidTemplate = AndroidTemplate.emptyActivity,
    // Flutter-specific options
    FlutterTemplate flutterTemplate = FlutterTemplate.counterApp,
    // React Native-specific options
    ReactNativeTemplate rnTemplate = ReactNativeTemplate.blank,
  }) async {
    final base = projectsBasePath ?? RuntimeEnvir.projectsPath;
    final projectPath = '$base/$name';
    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      sdk: sdk,
      path: projectPath,
      createdAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );

    // Build the create command — prefer the installed JSON extension's command.
    final def = ProjectTemplate.forSdk(sdk);
    final createCmd = def.createCommand(name, base,
        overrideNewProjectCmd: newProjectCmd,
        remoteIsWindows: remoteIsWindows,
        androidLanguage: androidLanguage,
        androidMinSdk: androidMinSdk,
        androidTemplate: androidTemplate,
        flutterTemplate: flutterTemplate,
        rnTemplate: rnTemplate);

    // Await the terminal callback so navigation only happens after the command
    // runs (or the session signals completion).
    await runInTerminal(createCmd);

    _projects.insert(0, project);
    await _saveProjects();
    notifyListeners();
    return project;
  }

  void openProject(Project project, {bool isNew = false}) {
    final updated = project.copyWith(lastOpenedAt: DateTime.now());
    final idx = _projects.indexWhere((p) => p.id == project.id);
    if (idx != -1) {
      _projects[idx] = updated;
      _saveProjects();
    }
    _activeProject = updated;
    _activeProjectIsNew = isNew;
    notifyListeners();
  }

  void closeProject() {
    _activeProject = null;
    notifyListeners();
  }

  Future<void> deleteProject(Project project) async {
    _projects.removeWhere((p) => p.id == project.id);
    if (_activeProject?.id == project.id) _activeProject = null;
    await _saveProjects();
    // Optionally delete files
    final dir = Directory(project.path);
    if (await dir.exists()) await dir.delete(recursive: true);
    notifyListeners();
  }

  /// Refresh the list of remote projects by listing [remotePath] via [listDir].
  Future<void> refreshRemoteProjects({
    required Future<List<Map<String, dynamic>>> Function(String path) listDir,
    required String remotePath,
  }) async {
    try {
      final entries = await listDir(remotePath);
      _remoteProjects.clear();
      for (final entry in entries) {
        if (entry['isDirectory'] == true) {
          final name = entry['name'] as String;
          final path = entry['path'] as String;
          _remoteProjects.add(Project(
            id: 'remote_${path.hashCode}',
            name: name,
            sdk: SdkType.flutter,
            path: path,
            createdAt: DateTime.now(),
            lastOpenedAt: DateTime.now(),
          ));
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  void clearRemoteProjects() {
    _remoteProjects.clear();
    notifyListeners();
  }

  /// Register a project that already exists on disk (e.g. after git clone).
  /// Detects SDK automatically from directory contents.
  Future<Project> addProjectFromPath(String path) async {
    final normalized = path.replaceAll('\\', '/');
    final existing = _projects.where((p) => p.path == normalized).firstOrNull;
    if (existing != null) return existing;

    final name = normalized.split('/').last;
    final sdk = await _detectSdk(normalized);
    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      sdk: sdk,
      path: normalized,
      createdAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );
    _projects.insert(0, project);
    await _saveProjects();
    notifyListeners();
    return project;
  }

  /// Detect SDK type from directory contents.
  static Future<SdkType> _detectSdk(String dirPath) async {
    if (await File('$dirPath/pubspec.yaml').exists()) return SdkType.flutter;
    if (await File('$dirPath/package.json').exists()) return SdkType.reactNative;
    if (await File('$dirPath/build.gradle.kts').exists() ||
        await File('$dirPath/app/build.gradle.kts').exists() ||
        await File('$dirPath/build.gradle').exists()) {
      return SdkType.androidSdk;
    }
    return SdkType.flutter; // reasonable default
  }

  /// Loads projects by merging SharedPreferences metadata with what is actually
  /// present in the projects directory.  Projects created via the terminal
  /// appear automatically; saved metadata (name, lastOpenedAt) is preserved.
  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('projects');

    // Build a map of path → saved Project for fast lookup.
    final saved = <String, Project>{};
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List;
        for (final j in list) {
          final p = Project.fromJson(j as Map<String, dynamic>);
          saved[p.path] = p;
        }
      } catch (_) {}
    }

    // Scan the projects directory on the filesystem.
    final projectsDir = Directory(RuntimeEnvir.projectsPath);
    final merged = <Project>[];
    if (await projectsDir.exists()) {
      final entries = projectsDir.listSync(followLinks: false);
      for (final entry in entries) {
        if (entry is! Directory) continue;
        final path = entry.path.replaceAll('\\', '/');
        if (saved.containsKey(path)) {
          merged.add(saved[path]!);
        } else {
          // Project on disk but not in saved list — auto-detect and register.
          final sdk = await _detectSdk(path);
          final name = path.split('/').last;
          final stat = await entry.stat();
          merged.add(Project(
            id: path.hashCode.abs().toString(),
            name: name,
            sdk: sdk,
            path: path,
            createdAt: stat.modified,
            lastOpenedAt: stat.modified,
          ));
        }
      }
    }

    // Sort most recently opened first.
    merged.sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    _projects.clear();
    _projects.addAll(merged);
    notifyListeners();
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'projects', jsonEncode(_projects.map((p) => p.toJson()).toList()));
  }
}
