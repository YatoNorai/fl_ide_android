// This file is kept for package exports but the primary projects UI
// is now in the HomeScreen's _ProjectsSheet bottom sheet.
// This screen is still usable as a standalone page if needed.

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/project_manager_provider.dart';
import 'create_project_dialog.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        title: const Text('Projects',
            style: TextStyle(color: AppTheme.darkText, fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppTheme.darkText),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CreateProjectScreen())),
            tooltip: 'New project',
          ),
        ],
      ),
      body: Consumer<ProjectManagerProvider>(
        builder: (context, pm, _) {
          if (pm.projects.isEmpty) {
            return const Center(
              child: Text('No projects yet',
                  style: TextStyle(color: AppTheme.darkTextMuted, fontSize: 16)),
            );
          }
          return ListView.separated(
            itemCount: pm.projects.length,
            separatorBuilder: (_, __) =>
                const Divider(color: AppTheme.darkDivider, height: 1),
            itemBuilder: (context, i) {
              final p = pm.projects[i];
              return ListTile(
                leading: Text(p.sdk.icon, style: const TextStyle(fontSize: 24)),
                title: Text(p.name,
                    style: const TextStyle(
                        color: AppTheme.darkText, fontSize: 16,
                        fontWeight: FontWeight.w500)),
                subtitle: Text(p.sdk.displayName,
                    style: const TextStyle(
                        color: AppTheme.darkTextMuted, fontSize: 12)),
                onTap: () => pm.openProject(p),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: AppTheme.darkTextMuted, size: 20),
                  onPressed: () => _showOptions(context, pm, p),
                ),
              );
            },
          );
        },
      ),
    );
  }

  void _showOptions(
      BuildContext context, ProjectManagerProvider pm, Project p) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.folder_open, color: AppTheme.darkAccent),
            title: const Text('Open',
                style: TextStyle(color: AppTheme.darkText)),
            onTap: () {
              Navigator.pop(ctx);
              pm.openProject(p);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: AppTheme.darkError),
            title: const Text('Delete',
                style: TextStyle(color: AppTheme.darkError)),
            onTap: () {
              Navigator.pop(ctx);
              pm.deleteProject(p);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
