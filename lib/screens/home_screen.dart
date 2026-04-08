import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:ssh_pkg/ssh_pkg.dart';

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
      /* backgroundColor: colors.surface, */
      appBar: AppBar(
        centerTitle: true,
      /*   backgroundColor: colors.surface, */
        title: Text(
  "L A Y E R",
  style: GoogleFonts.montserrat( // Ou .inter, .poppins, etc.
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 5.0,
    //color: Colors.white.withOpacity(0.9),
  ),
),
      ),
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                  //  mainAxisSize: MainAxisSize.min,
                    children: [
                       const SizedBox(height: 100),
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
                     Spacer(),
                      _homeOption(context,
                          title: s.newProject,
                          subtitle: s.newProjectSub,
                          onTap: () => _createProject(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(30),
                              bottom: Radius.circular(5)),
                          iconBg: Colors.blue,
                          icon: FontAwesomeIcons.folderPlus),
                      _homeOption(context,
                          title: s.openProject,
                          subtitle: s.openProjectSub,
                          onTap: () => _openProjects(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                              bottom: Radius.circular(5)),
                          iconBg: Colors.teal,
                          icon: FontAwesomeIcons.folderOpen),
                      _homeOption(context,
                          title: s.terminal,
                          subtitle: s.terminalSub,
                          onTap: () => _openTerminal(context),
                          borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(5),
                              bottom: Radius.circular(5)),
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
                              top: Radius.circular(5),
                              bottom: Radius.circular(30)),
                          iconBg: Colors.pink,
                          icon: FontAwesomeIcons.gear),
                      const SizedBox(height: 20),
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
      MaterialPageRoute(
        // Wrap with Consumer so the screen rebuilds when detectedSdks arrives
        // (SDK detection runs in background after connect).
        builder: (_) => Consumer<SshProvider>(
          builder: (ctx, ssh, _) => CreateProjectScreen(
            isSshActive: ssh.isConnected,
            remoteProjectsPath:
                ssh.isConnected ? ssh.config?.remoteProjectsPath : null,
            remoteSdkNames: ssh.isConnected ? ssh.detectedSdks : const [],
            isSshDetecting: ssh.isConnected && ssh.isDetectingSdks,
            remoteIsWindows: ssh.isConnected && ssh.remoteIsWindows,
            sshTerminalSetup: ssh.isConnected
                ? (session) async {
                    final sshSession = await ssh.startShell();
                    final controller = StreamController<List<int>>();
                    controller.stream.listen(
                      (bytes) =>
                          sshSession.stdin.add(Uint8List.fromList(bytes)),
                    );
                    session.attachRemote(
                      remoteOutput: sshSession.stdout.cast<List<int>>(),
                      remoteInput: controller.sink,
                      doneFuture: sshSession.done,
                      onResize: (w, h) => sshSession.resizeTerminal(w, h),
                    );
                  }
                : null,
          ),
        ),
      ),
    );
  }

  void _openProjects(BuildContext context) {
    final ssh = context.read<SshProvider>();
    final pm = context.read<ProjectManagerProvider>();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProjectsScreen(
          isSshActive: ssh.isConnected,
          sshHost: ssh.config?.host,
          sshProjects: pm.remoteProjects,
          onSshProjectTap: (project) {
            pm.openProject(project);
            Navigator.of(context).popUntil((r) => r.isFirst);
          },
          onRefreshSsh: () async {
            if (!ssh.isConnected || ssh.config == null) return;
            await pm.refreshRemoteProjects(
              listDir: (path) async {
                final entries = await ssh.listDirectory(path);
                return entries
                    .map((e) => {
                          'name': e.name,
                          'path': e.path,
                          'isDirectory': e.isDirectory,
                        })
                    .toList();
              },
              remotePath: ssh.config!.remoteProjectsPath,
            );
          },
        ),
      ),
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
  final colors = Theme.of(context).cardTheme;
  return Card(
  /*   elevation: 0, */
  //  color: colors.color?.withOpacity(0.5),
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 1),
    child: ListTile(
      tileColor: Colors.transparent,
      leading: CircleAvatar(
          backgroundColor: iconBg,
          child: FaIcon(icon, size: 16, color: Colors.white)),
      title: Text(title),
      subtitle: Padding(
        padding: const EdgeInsets.all(0),
        child: Text(subtitle, maxLines: 1),
      ),
      //trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

