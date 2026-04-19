import 'package:core/core.dart';
import 'package:fl_ide/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/project_manager_provider.dart';

class ProjectsScreen extends StatefulWidget {
  final bool isSshActive;
  final String? sshHost;
  /// Full Project objects from the remote machine (includes path).
  final List<Project> sshProjects;
  final void Function(Project project)? onSshProjectTap;
  final Future<void> Function()? onRefreshSsh;

  const ProjectsScreen({
    super.key,
    this.isSshActive = false,
    this.sshHost,
    this.sshProjects = const [],
    this.onSshProjectTap,
    this.onRefreshSsh,
  });

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Auto-load remote projects when the screen opens
    if (widget.isSshActive && widget.onRefreshSsh != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _doRefresh());
    }
  }

  Future<void> _doRefresh() async {
    if (!mounted || widget.onRefreshSsh == null) return;
    setState(() => _refreshing = true);
    await widget.onRefreshSsh!();
    if (mounted) setState(() => _refreshing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

    return Scaffold(
   //   backgroundColor: cs.surface,
      appBar: AppBar(
    //    backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
       
        title: Text(
  "L A Y E R",
  style: GoogleFonts.montserrat( // Ou .inter, .poppins, etc.
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 5.0,
  //  color: Colors.white.withOpacity(0.9),
  ),
),
      ),
      body: Consumer<ProjectManagerProvider>(
        builder: (context, pm, _) {
          final titleWidget = Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: Text(
              s.recentProjects,
              style: GoogleFonts.openSans(
                color: cs.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
          );

          // Estado vazio — título fixo, não há o que rolar
          if (pm.projects.isEmpty && !widget.isSshActive) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleWidget,
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_off_outlined,
                            size: 48, color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          s.noProjects,
                          style: GoogleFonts.openSans(
                              color: cs.onSurfaceVariant, fontSize: 15),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // SSH mode
          if (widget.isSshActive) {
            return _buildSshList(context, cs, pm, titleWidget);
          }

          // Lista local — título rola com a lista
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            children: [
              titleWidget,
              ...List.generate(pm.projects.length, (i) {
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
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                    onDelete: () => _confirmDelete(context, pm, p),
                  ),
                );
              }),
              const SizedBox(height: 100),
            ],
          );
        },
      ),
      extendBody: true,
      bottomNavigationBar:    Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
              children: [
                          
                OutlinedButton(
                  onPressed:
                       () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                  //  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: cs.surface,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                  child: Text(s.close),
                ),
               
              ],
            ),
              ),
    );
  }

  Widget _buildSshList(
      BuildContext context, ColorScheme cs, ProjectManagerProvider pm,
      Widget titleWidget) {
    final sshHeader = Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Row(
        children: [
          Icon(Icons.computer_rounded, size: 16, color: cs.secondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'SSH: ${widget.sshHost ?? ""}',
              style: GoogleFonts.openSans(
                color: cs.secondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_refreshing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (widget.onRefreshSsh != null)
            IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _doRefresh,
              tooltip: 'Refresh SSH projects',
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );

    if (pm.remoteProjects.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          titleWidget,
          sshHeader,
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_off_outlined,
                      size: 48, color: cs.outlineVariant),
                  const SizedBox(height: 12),
                  Text(
                    _refreshing ? 'Carregando...' : 'Nenhum projeto remoto encontrado',
                    style: GoogleFonts.openSans(
                        color: cs.onSurfaceVariant, fontSize: 15),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      children: [
        titleWidget,
        sshHeader,
        ...List.generate(pm.remoteProjects.length, (i) {
          final project = pm.remoteProjects[i];
          final isFirst = i == 0;
          final isLast = i == pm.remoteProjects.length - 1;
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
            child: _SshProjectTile(
              name: project.name,
              borderRadius: radius,
              onTap: widget.onSshProjectTap != null
                  ? () => widget.onSshProjectTap!(project)
                  : null,
            ),
          );
        }),
        const SizedBox(height: 100),
      ],
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
    final action = await showThemedDialog<String>(
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
                  style: GoogleFonts.openSans(color: cs.error)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action != 'delete' || !context.mounted) return;

    // Step 2: confirmation dialog
    final confirmed = await showThemedDialog<bool>(
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
   //   elevation: 0,
      margin: EdgeInsets.zero,
    //  color: cs.surfaceTint.withValues(alpha: 0.08),
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
                  style:  GoogleFonts.openSans(fontSize: 18),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      project.name,
                      style: GoogleFonts.openSans(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      project.sdk.displayName,
                      style: GoogleFonts.openSans(
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

// ── SSH project tile ──────────────────────────────────────────────────────────

class _SshProjectTile extends StatelessWidget {
  final String name;
  final BorderRadiusGeometry borderRadius;
  final VoidCallback? onTap;

  const _SshProjectTile({
    required this.name,
    required this.borderRadius,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      //elevation: 0,
      margin: EdgeInsets.zero,
     // color: cs.surfaceTint.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: InkWell(
        onTap: onTap,
        borderRadius: borderRadius as BorderRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: cs.primaryContainer.withValues(alpha: 0.6),
                child: const Icon(Icons.computer_rounded, size: 18),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.openSans(
                        color: cs.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Remote project',
                      style: GoogleFonts.openSans(
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
