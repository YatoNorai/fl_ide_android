import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../project_template.dart';

class ProjectManagerProvider extends ChangeNotifier {
  final List<Project> _projects = [];
  Project? _activeProject;

  List<Project> get projects => List.unmodifiable(_projects);
  Project? get activeProject => _activeProject;

  Future<void> initialize() async {
    await _loadProjects();
    await Directory(RuntimeEnvir.projectsPath).create(recursive: true);
  }

  Future<Project> createProject({
    required String name,
    required SdkType sdk,
    required void Function(String script) runInTerminal,
  }) async {
    final projectPath = '${RuntimeEnvir.projectsPath}/$name';
    final project = Project(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      sdk: sdk,
      path: projectPath,
      createdAt: DateTime.now(),
      lastOpenedAt: DateTime.now(),
    );

    // Build the create command using the SDK definition
    final def = ProjectTemplate.forSdk(sdk);
    final createCmd = def.createCommand(name, RuntimeEnvir.projectsPath);
    runInTerminal(createCmd);

    _projects.insert(0, project);
    await _saveProjects();
    notifyListeners();
    return project;
  }

  void openProject(Project project) {
    final updated = project.copyWith(lastOpenedAt: DateTime.now());
    final idx = _projects.indexWhere((p) => p.id == project.id);
    if (idx != -1) {
      _projects[idx] = updated;
      _saveProjects();
    }
    _activeProject = updated;
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

  Future<void> _loadProjects() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('projects');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _projects.clear();
      _projects.addAll(list.map((j) => Project.fromJson(j as Map<String, dynamic>)));
    }
    notifyListeners();
  }

  Future<void> _saveProjects() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('projects', jsonEncode(_projects.map((p) => p.toJson()).toList()));
  }
}
