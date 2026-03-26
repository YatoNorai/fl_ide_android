import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:project_manager/project_manager.dart';

import '../l10n/app_strings.dart';
import 'settings_screen.dart';
import 'standalone_terminal_screen.dart';

// ── Home screen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: colors.surface,
        title: Text('FL IDE',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ),
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
                        child: Image.asset('assets/logo.png',
                            width: 200,
                            height: 200,
                            fit: BoxFit.cover,
                            color: Theme.of(context)
                                .textTheme
                                .bodyLarge
                                ?.color),
                      ),
                      const SizedBox(height: 20),
                      _homeOption(context,
                          title: s.newProject,
                          subtitle: s.newProjectSub,
                          onTap: () => _createProject(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(30),
                              bottom: Radius.circular(10)),
                          iconBg: Colors.blue,
                          icon: FontAwesomeIcons.folderPlus),
                      _homeOption(context,
                          title: s.openProject,
                          subtitle: s.openProjectSub,
                          onTap: () => _openProjects(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                              bottom: Radius.circular(10)),
                          iconBg: Colors.teal,
                          icon: FontAwesomeIcons.folderOpen),
                      _homeOption(context,
                          title: s.terminal,
                          subtitle: s.terminalSub,
                          onTap: () => _openTerminal(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(10),
                              bottom: Radius.circular(10)),
                          iconBg: Colors.black,
                          icon: FontAwesomeIcons.terminal),
                      _homeOption(context,
                          title: s.settings,
                          subtitle: s.settingsSub,
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
                      const SizedBox(height: 100),
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
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProjectsScreen()),
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
        child: Text(title, ),
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

