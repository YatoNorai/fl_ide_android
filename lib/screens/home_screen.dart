import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';

import 'settings_screen.dart';
import 'standalone_terminal_screen.dart';

// ── Home screen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: colors.surface,
        title: Text( 'FL IDE',style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                           ),),),
      body: CustomScrollView(
        slivers: [
         
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Padding(
                      padding: const EdgeInsets.only(top: 16, bottom: 8),
                      child: Image.asset("assets/logo.png",width: 200, height: 200, fit: BoxFit.cover, ),
                    ),
                    SizedBox(height: 20,),
                      _homeOption(context,
                          title: 'New Project',
                          subtitle: 'Create a new project from a template',
                          onTap: () => _createProject(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(30),
                              bottom: Radius.circular(10)),
                          iconBg: Colors.blue,
                          icon: FontAwesomeIcons.folderPlus),
                      _homeOption(context,
                          title: 'Open Project',
                          subtitle: 'Open an existing project from storage',
                          onTap: () => _openProjects(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                              bottom: Radius.circular(10)),
                          iconBg: Colors.teal,
                          icon: FontAwesomeIcons.folderOpen),
                      _homeOption(context,
                          title: 'Terminal',
                          subtitle: 'Open a standalone shell session',
                          onTap: () => _openTerminal(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                              bottom: Radius.circular(10)),
                          iconBg: Colors.black,
                          icon: FontAwesomeIcons.terminal),
                      _homeOption(context,
                          title: 'Settings',
                          subtitle: 'Editor, appearance and extensions',
                          onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const SettingsScreen()),
                              ),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                              bottom: Radius.circular(30)),
                          iconBg: Colors.pink,
                          icon: FontAwesomeIcons.gear),
                            SizedBox(height: 100,),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _createProject(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
    );
  }

  void _openProjects(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ProjectsSheet(),
    );
  }

  void _openTerminal(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StandaloneTerminalScreen()),
    );
  }
}

// ── Home option card ──────────────────────────────────────────────────────────

Widget _homeOption(
  BuildContext context, {
  required String title,
  required String subtitle,
  required VoidCallback onTap,
  required Color iconBg,
  required IconData icon,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
}) {
  final colors = Theme.of(context).colorScheme;
  return Card(
    elevation: 0,
    color: colors.surfaceTint.withValues(alpha: 0.1),
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      leading: CircleAvatar(
          backgroundColor: iconBg,
          child: FaIcon(icon, size: 16, color: Colors.white)),
      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(title, style: const TextStyle(color: Colors.white)),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(subtitle, maxLines: 1),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

// ── Projects bottom sheet ─────────────────────────────────────────────────────

class _ProjectsSheet extends StatelessWidget {
  const _ProjectsSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectManagerProvider>(
      builder: (context, pm, _) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Text('Projects',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CreateProjectScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pm.projects.isEmpty
                  ? Center(
                      child: Text('No projects yet',
                          style: Theme.of(context).textTheme.bodyMedium),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: pm.projects.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = pm.projects[i];
                        return ListTile(
                          leading: Text(p.sdk.icon,
                              style: const TextStyle(fontSize: 24)),
                          title: Text(p.name),
                          subtitle: Text(p.sdk.displayName),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert, size: 20),
                            onPressed: () =>
                                _showDeleteOption(context, pm, p),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            pm.openProject(p);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteOption(
      BuildContext context, ProjectManagerProvider pm, Project p) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Open'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              pm.openProject(p);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
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
