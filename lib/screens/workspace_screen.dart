import 'package:app_installer/app_installer.dart';
import 'home_screen.dart' show SettingsScreen;
import 'package:build_runner_pkg/build_runner_pkg.dart';
import 'package:code_editor/code_editor.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:quill_code/quill_code.dart' show DiagnosticSeverity;
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/extensions_provider.dart';

/// AndroidIDE-style workspace:
/// - Narrow left icon rail (always visible)
/// - File tree slides in as an overlay from the left
/// - Editor takes the main space
/// - Bottom draggable sheet for Terminal/Build/Logs/Problems
class WorkspaceScreen extends StatefulWidget {
  final Project project;
  const WorkspaceScreen({super.key, required this.project});

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with TickerProviderStateMixin {
  bool _fileTreeOpen = false;
  late final TabController _bottomTabCtrl;
  final _sheetController = DraggableScrollableController();

  @override
  void initState() {
    super.initState();
    _bottomTabCtrl = TabController(length: 4, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final editor = context.read<EditorProvider>();
      await editor.loadProject(widget.project.path);
      if (!mounted) return;

      final def = SdkDefinition.forType(widget.project.sdk);
      final entryFile = '${widget.project.path}/${def.defaultEntryFile}';
      await editor.openFile(entryFile);
      if (!mounted) return;

      context.read<LspProvider>().startForExtension(
            def.defaultEntryFile.split('.').last,
            widget.project.path,
          );

      await context.read<TerminalProvider>().createSession(
            label: widget.project.name,
            workingDirectory: widget.project.path,
          );
    });
  }

  @override
  void dispose() {
    _bottomTabCtrl.dispose();
    _sheetController.dispose();
    super.dispose();
  }

  void _toggleFileTree() => setState(() => _fileTreeOpen = !_fileTreeOpen);

  void _closeFileTree() {
    if (_fileTreeOpen) setState(() => _fileTreeOpen = false);
  }

  void _expandBottomSheet() {
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.55,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: _WorkspaceAppBar(
        project: widget.project,
        onMenuTap: _toggleFileTree,
      ),
      body: Stack(
        children: [
          // ── Main: icon rail + editor + bottom sheet ──────────────────────
          Row(
            children: [
              // Left icon rail (always visible)
              _IconRail(
                project: widget.project,
                fileTreeOpen: _fileTreeOpen,
                onToggleFileTree: _toggleFileTree,
                onTabChange: (i) {
                  setState(() {
                    _bottomTabCtrl.index = i;
                    _expandBottomSheet();
                  });
                },
              ),
              // Editor + bottom sheet
              Expanded(
                child: GestureDetector(
                  // Swipe left to open file tree
                  onHorizontalDragEnd: (d) {
                    if ((d.primaryVelocity ?? 0) > 300) {
                      setState(() => _fileTreeOpen = true);
                    } else if ((d.primaryVelocity ?? 0) < -300) {
                      _closeFileTree();
                    }
                  },
                  child: Stack(
                    children: [
                      // Editor takes full area
                      Positioned.fill(
                        child: EditorArea(
                          editorTheme: context
                              .watch<ExtensionsProvider>()
                              .activeEditorTheme,
                        ),
                      ),
                      // Bottom draggable sheet
                      DraggableScrollableSheet(
                        controller: _sheetController,
                        initialChildSize: 0.11,
                        minChildSize: 0.09,
                        maxChildSize: 0.75,
                        snap: true,
                        snapSizes: const [0.11, 0.40, 0.75],
                        builder: (context, scrollController) =>
                            _BottomOutputSheet(
                          project: widget.project,
                          tabCtrl: _bottomTabCtrl,
                          scrollController: scrollController,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // ── File tree overlay (slides from left) ─────────────────────────
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            left: _fileTreeOpen ? 0 : -300,
            top: 0,
            bottom: 0,
            width: 300,
            child: Material(
              color: AppTheme.darkSidebar,
              elevation: 8,
              child: Column(
                children: [
                  // File tree header
                  Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      color: AppTheme.darkSidebar,
                      border: Border(
                          bottom: BorderSide(color: AppTheme.darkDivider)),
                    ),
                    child: Row(
                      children: [
                        const Text('File list',
                            style: TextStyle(
                                color: AppTheme.darkText,
                                fontSize: 16,
                                fontWeight: FontWeight.w600)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: AppTheme.darkText, size: 20),
                          onPressed: _closeFileTree,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                  ),
                  const Expanded(child: FileTreePanel()),
                ],
              ),
            ),
          ),

          // Tap outside file tree to close
          if (_fileTreeOpen)
            Positioned(
              left: 300,
              right: 0,
              top: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _closeFileTree,
                child: Container(color: Colors.transparent),
              ),
            ),
        ],
      ),
    );
  }
}

// ── AppBar ────────────────────────────────────────────────────────────────────

class _WorkspaceAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Project project;
  final VoidCallback onMenuTap;

  const _WorkspaceAppBar({required this.project, required this.onMenuTap});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 3);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppTheme.darkBg,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu, color: AppTheme.darkText, size: 24),
        onPressed: onMenuTap,
        tooltip: 'File Explorer',
      ),
      title: Text(
        project.name,
        style: const TextStyle(
            color: AppTheme.darkText,
            fontSize: 20,
            fontWeight: FontWeight.w700),
      ),
      actions: [
        // Stop/cancel build
        Consumer<BuildProvider>(
          builder: (context, build, _) => build.isBuilding
              ? IconButton(
                  icon: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.darkError, width: 2),
                    ),
                    child: const Icon(Icons.stop,
                        color: AppTheme.darkError, size: 12),
                  ),
                  onPressed: build.cancel,
                  tooltip: 'Stop build',
                )
              : const SizedBox.shrink(),
        ),
        // Hot reload
        Consumer<AppInstallerProvider>(
          builder: (context, installer, _) {
            if (!installer.hotReloadAvailable) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.refresh_rounded,
                  color: AppTheme.darkText, size: 24),
              onPressed: installer.hotReload,
              tooltip: 'Hot Reload',
            );
          },
        ),
        // More options
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: AppTheme.darkText, size: 24),
          color: AppTheme.darkSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onSelected: (val) {
            switch (val) {
              case 'build':
                context.read<BuildProvider>().build(project);
              case 'save':
                context.read<EditorProvider>().saveActiveFile();
              case 'close':
                context.read<ProjectManagerProvider>().closeProject();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'build',
              child: _PopupItem(
                  icon: Icons.play_arrow_rounded, label: 'Build project'),
            ),
            PopupMenuItem(
              value: 'save',
              child: _PopupItem(icon: Icons.save_outlined, label: 'Save file'),
            ),
            const PopupMenuDivider(),
            PopupMenuItem(
              value: 'close',
              child: _PopupItem(
                  icon: Icons.close, label: 'Close project',
                  color: AppTheme.darkError),
            ),
          ],
        ),
        const SizedBox(width: 4),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: Consumer<BuildProvider>(
          builder: (context, build, _) => build.isBuilding
              ? const LinearProgressIndicator(
                  color: AppTheme.darkAccent,
                  backgroundColor: Colors.transparent,
                  minHeight: 3,
                )
              : const SizedBox(height: 3),
        ),
      ),
    );
  }
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _PopupItem({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.darkText;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: c, fontSize: 14)),
      ],
    );
  }
}

// ── Left icon rail ────────────────────────────────────────────────────────────

class _IconRail extends StatelessWidget {
  final Project project;
  final bool fileTreeOpen;
  final VoidCallback onToggleFileTree;
  final ValueChanged<int> onTabChange;

  const _IconRail({
    required this.project,
    required this.fileTreeOpen,
    required this.onToggleFileTree,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 60,
      color: AppTheme.darkSideRail,
      child: Column(
        children: [
          const SizedBox(height: 8),
          // App logo
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppTheme.darkSurface,
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('FL',
                    style: TextStyle(
                        color: AppTheme.darkText,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // File tree icon
          _RailIcon(
            icon: Icons.folder_outlined,
            active: fileTreeOpen,
            onTap: onToggleFileTree,
            tooltip: 'File Explorer',
          ),
          // Android/Build icon
          _RailIcon(
            icon: Icons.android,
            onTap: () => onTabChange(1),
            tooltip: 'Build',
          ),
          // Terminal icon
          _RailIcon(
            icon: Icons.terminal,
            onTap: () => onTabChange(0),
            tooltip: 'Terminal',
          ),
          // Settings
          _RailIcon(
            icon: Icons.settings_outlined,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            tooltip: 'Settings',
          ),
          const Spacer(),
          // Close project
          _RailIcon(
            icon: Icons.close,
            onTap: () => context.read<ProjectManagerProvider>().closeProject(),
            tooltip: 'Close project',
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final String tooltip;

  const _RailIcon({
    required this.icon,
    this.active = false,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: active ? AppTheme.darkSurface : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 22,
              color: active ? AppTheme.darkText : AppTheme.darkTextMuted,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Bottom output sheet ───────────────────────────────────────────────────────

class _BottomOutputSheet extends StatelessWidget {
  final Project project;
  final TabController tabCtrl;
  final ScrollController scrollController;

  const _BottomOutputSheet({
    required this.project,
    required this.tabCtrl,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.darkPanel,
        border: Border(top: BorderSide(color: AppTheme.darkDivider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle area (collapsed state hint)
          SingleChildScrollView(
            controller: scrollController,
            physics: const NeverScrollableScrollPhysics(),
            child: Consumer<BuildProvider>(
              builder: (context, build, _) => Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Handle bar
                    Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.darkBorder,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      build.isBuilding
                          ? 'Building...'
                          : build.result.isSuccess
                              ? 'Build successful'
                              : build.result.isError
                                  ? 'Build failed'
                                  : 'Ready',
                      style: const TextStyle(
                          color: AppTheme.darkText,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Swipe up to view build output, logs and more.',
                      style: TextStyle(
                          color: AppTheme.darkTextMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Expanded: tab bar + content
          Expanded(
            child: Column(
              children: [
                // Tab bar
                Container(
                  height: 40,
                  color: AppTheme.darkSideRail,
                  child: TabBar(
                    controller: tabCtrl,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: EdgeInsets.zero,
                    labelColor: AppTheme.darkAccent,
                    unselectedLabelColor: AppTheme.darkTextMuted,
                    indicatorColor: AppTheme.darkAccent,
                    indicatorSize: TabBarIndicatorSize.label,
                    dividerColor: Colors.transparent,
                    labelStyle: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        letterSpacing: 0.5),
                    unselectedLabelStyle: const TextStyle(fontSize: 11),
                    tabs: const [
                      Tab(text: 'TERMINAL', height: 40),
                      Tab(text: 'BUILD', height: 40),
                      Tab(text: 'LOGS', height: 40),
                      Tab(text: 'PROBLEMS', height: 40),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppTheme.darkDivider),
                Expanded(
                  child: TabBarView(
                    controller: tabCtrl,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      const TerminalTabs(),
                      BuildPanel(project: project),
                      LogsPanel(
                          packageName: project.sdk == SdkType.flutter
                              ? 'com.example.${project.name}'
                              : null),
                      _ProblemsPanel(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Problems ──────────────────────────────────────────────────────────────────

class _ProblemsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        final ctrl = editor.activeFile?.controller;
        if (ctrl == null) {
          return const _PanelPlaceholder(
              icon: Icons.info_outline, text: 'No file open');
        }
        return ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            final diagnostics = ctrl.diagnostics.all;
            if (diagnostics.isEmpty) {
              return const _PanelPlaceholder(
                  icon: Icons.check_circle_outline,
                  iconColor: AppTheme.darkSuccess,
                  text: 'No problems');
            }
            return ListView.separated(
              itemCount: diagnostics.length,
              separatorBuilder: (_, __) =>
                  const Divider(color: AppTheme.darkDivider, height: 1),
              itemBuilder: (context, i) {
                final d = diagnostics[i];
                final isError = d.severity == DiagnosticSeverity.error;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isError ? Icons.error_outline : Icons.warning_amber_outlined,
                    size: 16,
                    color: isError ? AppTheme.darkError : AppTheme.darkWarning,
                  ),
                  title: Text(d.message,
                      style: const TextStyle(
                          color: AppTheme.darkText, fontSize: 12)),
                  subtitle: Text('Line ${d.range.start.line + 1}',
                      style: const TextStyle(
                          color: AppTheme.darkTextMuted, fontSize: 11)),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PanelPlaceholder extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String text;
  const _PanelPlaceholder(
      {required this.icon, this.iconColor, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: iconColor ?? AppTheme.darkTextDim),
          const SizedBox(height: 8),
          Text(text,
              style: const TextStyle(
                  color: AppTheme.darkTextMuted, fontSize: 13)),
        ],
      ),
    );
  }
}

// ── Settings screen (import from home_screen) ─────────────────────────────────
// Re-exported so workspace can navigate to it.
