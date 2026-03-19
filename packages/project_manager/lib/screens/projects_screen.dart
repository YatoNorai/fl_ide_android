import 'package:core/core.dart';
import 'package:fl_ide/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/project_manager_provider.dart';
import 'create_project_dialog.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'FL IDE',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: Consumer<ProjectManagerProvider>(
        builder: (context, pm, _) {
          final s = AppStrings.of(context);
          return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Text(
                s.recentProjects,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: pm.projects.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.folder_off_outlined,
                              size: 48, color: cs.outlineVariant),
                          const SizedBox(height: 12),
                          Text(
                            s.noProjects,
                            style: TextStyle(
                                color: cs.onSurfaceVariant, fontSize: 15),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      itemCount: pm.projects.length,
                      itemBuilder: (context, i) {
                        final p = pm.projects[i];
                        final isFirst = i == 0;
                        final isLast = i == pm.projects.length - 1;
                        final radius = BorderRadius.vertical(
                          top: isFirst
                              ? const Radius.circular(20)
                              : const Radius.circular(4),
                          bottom: isLast
                              ? const Radius.circular(20)
                              : const Radius.circular(4),
                        );
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: _ProjectTile(
                            project: p,
                            borderRadius: radius,
                            onTap: () {
                              pm.openProject(p);
                              Navigator.of(context)
                                  .popUntil((r) => r.isFirst);
                            },
                            onDelete: () =>
                                _confirmDelete(context, pm, p),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    ProjectManagerProvider pm,
    Project p,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

    // Step 1: long-press options dialog
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.delete_outline, color: cs.error),
              title: Text(s.delete,
                  style: TextStyle(color: cs.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action != 'delete' || !context.mounted) return;

    // Step 2: confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final s2 = AppStrings.of(ctx);
        return AlertDialog(
          title: Text(s2.deleteProjectQ),
          content: Text(s2.deleteProjectSub),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s2.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s2.delete),
            ),
          ],
        );
      },
    );
    if (confirmed == true && context.mounted) {
      pm.deleteProject(p);
    }
  }
}

// ── Project tile ──────────────────────────────────────────────────────────────

class _ProjectTile extends StatelessWidget {
  final Project project;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ProjectTile({
    required this.project,
    required this.borderRadius,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceTint.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: InkWell(
        onTap: onTap,
        onLongPress: onDelete,
        borderRadius: borderRadius as BorderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor:
                    cs.primaryContainer.withValues(alpha: 0.6),
                child: Text(
                  project.sdk.icon,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.sdk.displayName,
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: cs.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }
}
