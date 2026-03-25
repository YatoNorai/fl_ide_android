import 'package:app_installer/app_installer.dart';
import 'package:build_runner_pkg/build_runner_pkg.dart';
import 'package:code_editor/code_editor.dart';
import 'package:core/core.dart';
import 'package:fl_ide/screens/standalone_terminal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:quill_code/quill_code.dart'
    show DiagnosticSeverity, QuillActionsMenu, QuillThemeDark, SearchOptions;
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../l10n/app_strings.dart';
import '../providers/extensions_provider.dart';
import '../providers/settings_provider.dart';
import 'settings_screen.dart' show SettingsScreen;

const _kDrawerWidth = 300.0;
const _kRailWidth = 64.0;
const _kSpecialChars = [
  '(', ')', '{', '}', '[', ']', ';', ':',
  '.', ',', '<', '>', '=', '!', '&', '|',
  '+', '-', '*', '/', r'\', '_', '"', "'",
  '#', '@', r'$', '%', '^', '~', '?', '\t',
];

// Init phases shown in the peek bar
enum _InitPhase { creatingProject, loadingProject, startingLsp, ready }

class WorkspaceScreen extends StatefulWidget {
  final Project project;
  final bool isNewProject;
  const WorkspaceScreen({
    super.key,
    required this.project,
    this.isNewProject = false,
  });

  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen>
    with TickerProviderStateMixin {
  late final AnimationController _drawerCtrl;
  late final Animation<double> _drawerAnim;
  late final TabController _bottomTabCtrl;
  final _sheetKey = GlobalKey<_BottomSheetPanelState>();
  _InitPhase _initPhase = _InitPhase.loadingProject;

  @override
  void initState() {
    super.initState();
    _bottomTabCtrl = TabController(length: 4, vsync: this);
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _drawerAnim = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeInOut,
    );

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Phase 1: creating / loading project
      if (widget.isNewProject) {
        setState(() => _initPhase = _InitPhase.creatingProject);
      } else {
        setState(() => _initPhase = _InitPhase.loadingProject);
      }

      final editor = context.read<EditorProvider>();
      await editor.loadProject(widget.project.path);
      if (!mounted) return;

      final def = SdkDefinition.forType(widget.project.sdk);
      final entryFile = '${widget.project.path}/${def.defaultEntryFile}';
      await editor.openFile(entryFile);
      if (!mounted) return;

      // Phase 2: starting LSP
      setState(() => _initPhase = _InitPhase.startingLsp);
      final settings = context.read<SettingsProvider>();
      await context.read<LspProvider>().startForExtension(
            def.defaultEntryFile.split('.').last,
            widget.project.path,
            customPaths: settings.lspPaths,
          );
      if (!mounted) return;
      setState(() => _initPhase = _InitPhase.ready);

      // Phase 3: create terminal and cd to project directory
      final session = await context.read<TerminalProvider>().createSession(
            label: widget.project.name,
            workingDirectory: widget.project.path,
          );
      // Explicit cd ensures correct directory even if shell sources .bashrc
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        session.writeCommand('cd "${widget.project.path}"');
      }
    });
  }

  @override
  void dispose() {
    _drawerCtrl.dispose();
    _bottomTabCtrl.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    super.dispose();
  }

  void _closeDrawer() => _drawerCtrl.reverse();
  void _toggleDrawer() {
    if (_drawerCtrl.isCompleted) {
      _drawerCtrl.reverse();
    } else {
      _drawerCtrl.forward();
    }
  }

  void _expandBottomSheet() {
    _sheetKey.currentState?.expandToMid();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 150;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        if (_drawerCtrl.isCompleted) _closeDrawer();
      },
      child: Scaffold(
        body: AnimatedBuilder(
          animation: _drawerAnim,
          builder: (context, _) {
            final cs = Theme.of(context).colorScheme;
            final v = _drawerAnim.value;
            return Stack(
              children: [
                // ── Main content (AppBar + editor) slides right ────────────
                Transform.translate(
                  offset: Offset(v * _kDrawerWidth, 0),
                  child: ColoredBox(
                    color: cs.surface,
                    child: SafeArea(
                    child: Column(
                      children: [
                        _WorkspaceAppBar(
                          project: widget.project,
                          drawerAnim: _drawerAnim,
                          onMenuTap: _toggleDrawer,
                        ),
                        Expanded(
                          child: _MainContent(
                            project: widget.project,
                            bottomTabCtrl: _bottomTabCtrl,
                            sheetKey: _sheetKey,
                            keyboardVisible: keyboardVisible,
                            initPhase: _initPhase,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ),
                ),

                // ── Drawer ────────────────────────────────────────────────
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: _kDrawerWidth,
                  child: Transform.translate(
                    offset: Offset((v - 1) * _kDrawerWidth, 0),
                    child: ColoredBox(
                      color: cs.surfaceContainerLow,
                      child: Builder(builder: (context) {
                        final pad = MediaQuery.of(context).padding;
                        return Padding(
                          padding: EdgeInsets.only(
                              top: pad.top, bottom: pad.bottom),
                          child: _DrawerContent(
                            project: widget.project,
                            onClose: _closeDrawer,
                            onTabChange: (i) {
                              setState(() => _bottomTabCtrl.index = i);
                              _closeDrawer();
                              _expandBottomSheet();
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                ),

                // ── Scrim ──────────────────────────────────────────────────
                if (v > 0)
                  Positioned.fill(
                    left: _kDrawerWidth * v,
                    child: GestureDetector(
                      onTap: _closeDrawer,
                      child: ColoredBox(
                        color:
                            Colors.black.withValues(alpha: v * 0.38),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── AppBar (fixed-height custom widget — AppBar widget cannot be used outside
//    Scaffold.appBar because it uses Expanded internally, causing unbounded
//    height errors in a Column) ───────────────────────────────────────────────

class _WorkspaceAppBar extends StatefulWidget {
  final Project project;
  final Animation<double> drawerAnim;
  final VoidCallback onMenuTap;

  const _WorkspaceAppBar({
    required this.project,
    required this.drawerAnim,
    required this.onMenuTap,
  });

  @override
  State<_WorkspaceAppBar> createState() => _WorkspaceAppBarState();
}

class _WorkspaceAppBarState extends State<_WorkspaceAppBar> {
  bool _searchMode = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _enterSearch() {
    setState(() => _searchMode = true);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _searchFocus.requestFocus());
  }

  void _exitSearch() {
    final ctrl = context.read<EditorProvider>().activeFile?.controller;
    ctrl?.searcher.stopSearch();
    setState(() {
      _searchMode = false;
      _searchCtrl.clear();
    });
  }

  void _onSearchChanged(String q) {
    final ctrl = context.read<EditorProvider>().activeFile?.controller;
    if (ctrl == null) return;
    if (q.isEmpty) {
      ctrl.searcher.stopSearch();
    } else {
      ctrl.searcher.search(q, const SearchOptions());
    }
  }

  void _searchNext() {
    final ctrl = context.read<EditorProvider>().activeFile?.controller;
    if (ctrl == null) return;
    final result = ctrl.searcher.gotoNext(ctrl.cursor.position);
    if (result != null) ctrl.setCursor(result.start);
  }

  void _searchPrev() {
    final ctrl = context.read<EditorProvider>().activeFile?.controller;
    if (ctrl == null) return;
    final result = ctrl.searcher.gotoPrevious(ctrl.cursor.position);
    if (result != null) ctrl.setCursor(result.start);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      
      child: SizedBox(
        height: kToolbarHeight + 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: _searchMode
                  ? _buildSearchBar(cs)
                  : _buildNormalBar(cs),
            ),
            Consumer<BuildProvider>(
              builder: (context, build, _) => build.isBuilding
                  ? LinearProgressIndicator(
                      color: cs.primary,
                      backgroundColor: Colors.transparent,
                      minHeight: 3,
                    )
                  : const SizedBox(height: 3),
            ),
          ],
        ),
        
      ),
    
    );
  }

  Widget _buildSearchBar(ColorScheme cs) {
    return Row(
      children: [
        IconButton(
          icon: Icon(Icons.arrow_back, color: cs.onSurface, size: 22),
          onPressed: _exitSearch,
          tooltip: 'Close search',
        ),
        Expanded(
          child: TextField(
            controller: _searchCtrl,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            onSubmitted: (_) => _searchNext(),
            decoration: InputDecoration(
              hintText: 'Search in file…',
              hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            style: TextStyle(color: cs.onSurface, fontSize: 14),
          ),
        ),
        IconButton(
          icon: Icon(Icons.keyboard_arrow_up, color: cs.onSurface),
          onPressed: _searchPrev,
          tooltip: 'Previous match',
        ),
        IconButton(
          icon: Icon(Icons.keyboard_arrow_down, color: cs.onSurface),
          onPressed: _searchNext,
          tooltip: 'Next match',
        ),
      ],
    );
  }

  Widget _buildNormalBar(ColorScheme cs) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        final ctrl = editor.activeFile?.controller;
        if (ctrl == null) return _buildToolbar(context, cs, false, false);
        return ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) =>
              _buildToolbar(context, cs, ctrl.content.canUndo, ctrl.content.canRedo),
        );
      },
    );
  }

  Widget _buildToolbar(
      BuildContext context, ColorScheme cs, bool canUndo, bool canRedo) {
    return Row(
      children: [
        // ── Menu / back-arrow button ──────────────────────────────
        AnimatedBuilder(
          animation: widget.drawerAnim,
          builder: (_, __) => IconButton(
            icon: AnimatedIcon(
              icon: AnimatedIcons.menu_arrow,
              progress: widget.drawerAnim,
              size: 24,
            ),
            onPressed: widget.onMenuTap,
            tooltip: 'File Explorer',
          ),
        ),
        // ── Left label: FL IDE + project name ─────────────────────
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'FL IDE',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              Text(
                widget.project.name,
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 11,
                  height: 1.2,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        // ── Right buttons (state-dependent) ───────────────────────
        if (canUndo)
          IconButton(
            icon: Icon(Icons.undo_rounded, color: cs.onSurface, size: 22),
            onPressed: () => context.read<EditorProvider>().undo(),
            tooltip: 'Undo',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        if (canRedo)
          IconButton(
            icon: Icon(Icons.redo_rounded, color: cs.onSurface, size: 22),
            onPressed: () => context.read<EditorProvider>().redo(),
            tooltip: 'Redo',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        // ── Hot reload (if available) ──────────────────────────────
        Consumer<AppInstallerProvider>(
          builder: (_, installer, __) => installer.hotReloadAvailable
              ? IconButton(
                  icon: Icon(Icons.refresh_rounded,
                      color: cs.primary, size: 22),
                  onPressed: installer.hotReload,
                  tooltip: 'Hot Reload',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                )
              : const SizedBox.shrink(),
        ),
        // ── Build / Stop button ────────────────────────────────────
        Consumer<BuildProvider>(
          builder: (context, build, _) => build.isBuilding
              ? IconButton(
                  icon: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: cs.error, width: 2),
                    ),
                    child: Icon(Icons.stop, color: cs.error, size: 11),
                  ),
                  onPressed: build.cancel,
                  tooltip: 'Stop build',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                )
              : IconButton(
                  icon: Icon(Icons.play_arrow_rounded,
                      color: cs.primary, size: 24),
                  onPressed: () =>
                      context.read<BuildProvider>().build(widget.project),
                  tooltip: 'Build project',
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
        ),
        // ── Type commands (only when not at max buttons) ───────────
        if (!canRedo)
          IconButton(
            icon: Icon(Icons.terminal_outlined, color: cs.onSurface, size: 20),
            onPressed: () {
              final editor = context.read<EditorProvider>();
              final ctrl = editor.activeFile?.controller;
              if (ctrl == null) return;
              final theme =
                  context.read<ExtensionsProvider>().activeEditorTheme ??
                      QuillThemeDark.build();
              QuillActionsMenu.show(context, ctrl, theme);
            },
            tooltip: 'Commands',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        // ── Search (only in normal state) ──────────────────────────
        if (!canUndo)
          IconButton(
            icon: Icon(Icons.search_rounded, color: cs.onSurface, size: 22),
            onPressed: _enterSearch,
            tooltip: 'Search',
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          ),
        // ── 3-dot overflow menu ────────────────────────────────────
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, color: cs.onSurface, size: 22),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onSelected: (val) {
            final editor = context.read<EditorProvider>();
            switch (val) {
              case 'undo':
                editor.undo();
              case 'redo':
                editor.redo();
              case 'save':
                editor.saveActiveFile();
              case 'sync':
                editor.loadProject(widget.project.path);
              case 'search':
                _enterSearch();
              case 'commands':
                final ctrl = editor.activeFile?.controller;
                if (ctrl == null) return;
                final theme =
                    context.read<ExtensionsProvider>().activeEditorTheme ??
                        QuillThemeDark.build();
                QuillActionsMenu.show(context, ctrl, theme);
              case 'close':
                _confirmCloseProject(context);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'undo',
              height: 40,
              child: _PopupItem(icon: Icons.undo_rounded, label: 'Undo'),
            ),
            const PopupMenuItem(
              value: 'redo',
              height: 40,
              child: _PopupItem(icon: Icons.redo_rounded, label: 'Redo'),
            ),
            const PopupMenuItem(
              value: 'save',
              height: 40,
              child: _PopupItem(icon: Icons.save_outlined, label: 'Save'),
            ),
            const PopupMenuItem(
              value: 'sync',
              height: 40,
              child: _PopupItem(
                  icon: Icons.sync_rounded, label: 'Sync project'),
            ),
            if (canUndo)
              const PopupMenuItem(
                value: 'search',
                height: 40,
                child:
                    _PopupItem(icon: Icons.search_rounded, label: 'Search'),
              ),
            if (canRedo)
              const PopupMenuItem(
                value: 'commands',
                height: 40,
                child: _PopupItem(
                    icon: Icons.terminal_outlined, label: 'Commands'),
              ),
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'close',
              height: 40,
              child: _PopupItem(
                  icon: Icons.close,
                  label: 'Close project',
                  isDestructive: true),
            ),
          ],
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}

Future<void> _confirmCloseProject(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Close project'),
      content: const Text('Are you sure you want to close the current project? Any unsaved changes will be lost.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text('No', style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Yes, close'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    context.read<ProjectManagerProvider>().closeProject();
  }
}

class _PopupItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDestructive;
  const _PopupItem(
      {required this.icon, required this.label, this.isDestructive = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = isDestructive ? cs.error : cs.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(color: c, fontSize: 14)),
      ],
    );
  }
}

// ── Main content ──────────────────────────────────────────────────────────────

class _MainContent extends StatelessWidget {
  final Project project;
  final TabController bottomTabCtrl;
  final GlobalKey<_BottomSheetPanelState> sheetKey;
  final bool keyboardVisible;
  final _InitPhase initPhase;

  const _MainContent({
    required this.project,
    required this.bottomTabCtrl,
    required this.sheetKey,
    required this.keyboardVisible,
    required this.initPhase,
  });

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          Positioned.fill(
            child: EditorArea(
              editorTheme:
                  context.watch<ExtensionsProvider>().activeEditorTheme,
              showSymbolBar: false,
              fontSize: settings.fontSize,
              fontFamily: settings.fontFamily,
              configureProps: settings.applyToProps,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomSheetPanel(
              key: sheetKey,
              availableHeight: constraints.maxHeight,
              project: project,
              tabCtrl: bottomTabCtrl,
              keyboardVisible: keyboardVisible,
              initPhase: initPhase,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drawer content ────────────────────────────────────────────────────────────

class _DrawerContent extends StatelessWidget {
  final Project project;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChange;

  const _DrawerContent({
    required this.project,
    required this.onClose,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        // Icon rail — 64px
        _DrawerRail(
          project: project,
          onClose: onClose,
          onTabChange: onTabChange,
        ),
        // Divider
        VerticalDivider(width: 1, thickness: 1, color: cs.outlineVariant),
        // File tree with 2D scroll
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  project.name,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 600,
                    child: FileTreePanel(onFileSelected: onClose),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DrawerRail extends StatelessWidget {
  final Project project;
  final VoidCallback onClose;
  final ValueChanged<int> onTabChange;

  const _DrawerRail({
    required this.project,
    required this.onClose,
    required this.onTabChange,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: _kRailWidth,
      child: Container(
        color: cs.surfaceContainerLow,
        child: Column(
          children: [
            const SizedBox(height: 16),
            // ── App logo at top ──────────────────────────────────────────
            Tooltip(
              message: 'FL IDE',
              child: CircleAvatar(
                backgroundColor: cs.primary,
                radius: 22,
              child:Image.asset("assets/logo.png",width: 200, height: 200, fit: BoxFit.cover, ),
              ),
            ),
            const Spacer(),
            // ── Action buttons at bottom (colored circles) ───────────────
            _CircleRailBtn(
              icon: Icons.terminal,
              tooltip: 'Terminal',
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
              onTap: () =>  Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const StandaloneTerminalScreen()),
    ),
            ),
            _CircleRailBtn(
              icon: Icons.android,
              tooltip: 'Build',
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
              onTap: () => onTabChange(1),
            ),
            _CircleRailBtn(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
              onTap: () {
                onClose();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            _CircleRailBtn(
              icon: Icons.close,
              tooltip: 'Close project',
              bg: cs.errorContainer,
              fg: cs.onErrorContainer,
              onTap: () => _confirmCloseProject(context),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _CircleRailBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color bg;
  final Color fg;
  final VoidCallback onTap;

  const _CircleRailBtn({
    required this.icon,
    required this.tooltip,
    required this.bg,
    required this.fg,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: CircleAvatar(
            backgroundColor: bg,
            radius: 22,
            child: Icon(icon, color: fg, size: 20),
          ),
        ),
      ),
    );
  }
}

// ── Bottom sheet panel (persistent, draggable, snapping) ─────────────────────

class _BottomSheetPanel extends StatefulWidget {
  final double availableHeight;
  final Project project;
  final TabController tabCtrl;
  final bool keyboardVisible;
  final _InitPhase initPhase;

  const _BottomSheetPanel({
    super.key,
    required this.availableHeight,
    required this.project,
    required this.tabCtrl,
    required this.keyboardVisible,
    required this.initPhase,
  });

  @override
  State<_BottomSheetPanel> createState() => _BottomSheetPanelState();
}

class _BottomSheetPanelState extends State<_BottomSheetPanel>
    with SingleTickerProviderStateMixin {
  static const double _kPeek = 60.0;
  static const double _kMid = 400.0;
  static const double _kPeekBarH = 64.0;

  double _height = _kPeek;
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animCtrl.addListener(() => setState(() => _height = _anim.value));
  }

  @override
  void didUpdateWidget(_BottomSheetPanel old) {
    super.didUpdateWidget(old);
    if (_height > widget.availableHeight) {
      _height = widget.availableHeight;
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  /// Called externally (e.g. from drawer rail) to expand to mid stage.
  void expandToMid() => _snapTo(_kMid);

  List<double> get _snapPoints => [_kPeek, _kMid, widget.availableHeight];

  // 0.0 while in stages 1 & 2, ramps to 1.0 as stage 3 is entered
  double get _stage3Progress {
    if (_height <= _kMid) return 0.0;
    final full = widget.availableHeight;
    if (_height >= full) return 1.0;
    return (_height - _kMid) / (full - _kMid);
  }

  void _snapTo(double target) {
    final end = target.clamp(_kPeek, widget.availableHeight);
    _anim = Tween<double>(begin: _height, end: end)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    _animCtrl.forward(from: 0);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _animCtrl.stop();
    setState(() {
      _height =
          (_height - d.delta.dy).clamp(_kPeek, widget.availableHeight);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final snaps = _snapPoints;
    double target;
    if (v < -600) {
      final higher = snaps.where((s) => s > _height + 10).toList();
      target = higher.isNotEmpty ? higher.first : snaps.last;
    } else if (v > 600) {
      final lower = snaps.where((s) => s < _height - 10).toList();
      target = lower.isNotEmpty ? lower.last : snaps.first;
    } else {
      target = snaps.reduce((a, b) =>
          (a - _height).abs() < (b - _height).abs() ? a : b);
    }
    _snapTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DragTarget<OpenFile>(
      onAcceptWithDetails: (details) {
        final editor = context.read<EditorProvider>();
        final idx = editor.openFiles.indexOf(details.data);
        if (idx != -1) editor.moveToPanel(idx, bottom: true);
      },
      builder: (context, candidates, _) {
        final isDragOver = candidates.isNotEmpty;
        return SizedBox(
          height: _height,
          child: ClipRect(
            child: Material(
              color: isDragOver
                  ? cs.primaryContainer.withValues(alpha: 0.15)
                  : cs.surfaceContainerLow,
              child: Column(
                children: [
                  // ── Draggable header (drag anywhere here to resize) ──
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragUpdate: _onDragUpdate,
                    onVerticalDragEnd: _onDragEnd,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Consumer<LspProvider>(
                          builder: (ctx, lsp, _) {
                            if (lsp.status == LspStatus.starting) {
                              return LinearProgressIndicator(
                                minHeight: 2,
                                backgroundColor: cs.outlineVariant,
                              );
                            }
                            return Divider(
                                height: 1,
                                thickness: 1,
                                color: cs.outlineVariant);
                          },
                        ),

                        // ── Stage 1: peek bar (or symbol bar when keyboard up)
                        // When stage 3 begins the peek bar slides downward
                        // behind the tab bar and the SizedBox collapses it.  ─
                        if (widget.keyboardVisible)
                          const _SpecialCharsBar()
                        else
                          Builder(builder: (context) {
                            final p3 = _stage3Progress;
                            if (p3 >= 1.0) return const SizedBox.shrink();
                            return ClipRect(
                              child: SizedBox(
                                height: _kPeekBarH * (1.0 - p3),
                                width: double.infinity,
                                child: Transform.translate(
                                  offset: Offset(0, _kPeekBarH * p3),
                                  child: _PeekBar(initPhase: widget.initPhase),
                                ),
                              ),
                            );
                          }),

                        // ── Stage 2: tab bar — always rendered below ─────────
                        ...[
                          Consumer<EditorProvider>(
                            builder: (ctx, editor, _) {
                              final bf = editor.bottomPanelFiles;
                              if (bf.isEmpty) return const SizedBox.shrink();
                              return _BottomFileTabs(
                                  files: bf, editor: editor);
                            },
                          ),
                          ColoredBox(
                            color: cs.surfaceContainerHigh,
                            child: TabBar(
                              controller: widget.tabCtrl,
                              isScrollable: true,
                              tabAlignment: TabAlignment.start,
                              padding: EdgeInsets.zero,
                              dividerColor: Colors.transparent,
                              labelStyle: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5),
                              unselectedLabelStyle:
                                  const TextStyle(fontSize: 11),
                              tabs: const [
                                Tab(text: 'TERMINAL', height: 40),
                                Tab(text: 'BUILD', height: 40),
                                Tab(text: 'LOGS', height: 40),
                                Tab(text: 'PROBLEMS', height: 40),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // ── Content ──────────────────────────────────────────
                  Divider(height: 1, color: cs.outlineVariant),
                  Expanded(
                    child: TabBarView(
                      controller: widget.tabCtrl,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        const TerminalTabs(),
                        BuildPanel(project: widget.project),
                        LogsPanel(
                          packageName:
                              widget.project.sdk == SdkType.flutter
                                  ? 'com.example.${widget.project.name}'
                                  : null,
                        ),
                        _ProblemsPanel(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Peek bar shown at the collapsed (60 dp) stage ────────────────────────────

class _PeekBar extends StatelessWidget {
  final _InitPhase initPhase;
  const _PeekBar({required this.initPhase});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

    final String label;
    final bool showProgress;
    switch (initPhase) {
      case _InitPhase.creatingProject:
        label = s.peekCreatingProject;
        showProgress = false;
      case _InitPhase.loadingProject:
        label = s.peekLoadingProject;
        showProgress = false;
      case _InitPhase.startingLsp:
        label = s.peekStartingLsp;
        showProgress = true;
      case _InitPhase.ready:
        label = s.peekReady;
        showProgress = false;
    }

    return SizedBox(
      height: _BottomSheetPanelState._kPeekBarH,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (showProgress) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: LinearProgressIndicator(
                minHeight: 2,
                backgroundColor: cs.outlineVariant,
                color: cs.primary,
              ),
            ),
          ] else ...[
            const SizedBox(height: 3),
            Text(
              s.peekSwipeUp,
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bottom-panel file tabs ────────────────────────────────────────────────────

class _BottomFileTabs extends StatelessWidget {
  final List<OpenFile> files;
  final EditorProvider editor;

  const _BottomFileTabs({required this.files, required this.editor});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surfaceContainer,
      child: SizedBox(
        height: 36,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: files.length,
          itemBuilder: (context, i) {
            final f = files[i];
            final globalIndex = editor.openFiles.indexOf(f);
            final isActive = editor.activeFile?.path == f.path;
            return LongPressDraggable<OpenFile>(
              data: f,
              feedback: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(8),
                color: cs.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  child: Text(f.name,
                      style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              onDragEnd: (details) {
                // If dragged upward far enough, move back to top bar
                if (details.velocity.pixelsPerSecond.dy < -200) {
                  editor.moveToPanel(globalIndex, bottom: false);
                }
              },
              child: GestureDetector(
                onTap: () => editor.switchTo(globalIndex),
                child: Container(
                  height: 36,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color:
                            isActive ? cs.primary : Colors.transparent,
                        width: 2,
                      ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f.name,
                        style: TextStyle(
                          color: isActive
                              ? cs.primary
                              : cs.onSurfaceVariant,
                          fontSize: 11,
                          fontWeight: isActive
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Move back to top bar
                      GestureDetector(
                        onTap: () => editor.moveToPanel(globalIndex,
                            bottom: false),
                        child: Icon(Icons.arrow_upward_rounded,
                            size: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Sheet header: special chars bar ──────────────────────────────────────────

class _SpecialCharsBar extends StatelessWidget {
  const _SpecialCharsBar();

  void _insertChar(BuildContext context, String char) {
    final ctrl = context.read<EditorProvider>().activeFile?.controller;
    if (ctrl == null) return;
    if (char == '\t') {
      ctrl.insertTab();
    } else {
      ctrl.insertText(char);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: _kSpecialChars.length,
        itemBuilder: (context, i) {
          final char = _kSpecialChars[i];
          return InkWell(
            onTap: () => _insertChar(context, char),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              width: 36,
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                char == '\t' ? '⇥' : char,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Problems panel ────────────────────────────────────────────────────────────

class _ProblemsPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        final ctrl = editor.activeFile?.controller;
        if (ctrl == null) {
          return _PanelPlaceholder(
              icon: Icons.info_outline, text: 'No file open');
        }
        return ListenableBuilder(
          listenable: ctrl,
          builder: (context, _) {
            final diagnostics = ctrl.diagnostics.all;
            if (diagnostics.isEmpty) {
              return _PanelPlaceholder(
                icon: Icons.check_circle_outline,
                iconColor: cs.primary,
                text: 'No problems',
              );
            }
            return ListView.separated(
              itemCount: diagnostics.length,
              separatorBuilder: (_, __) =>
                  Divider(color: cs.outlineVariant, height: 1),
              itemBuilder: (context, i) {
                final d = diagnostics[i];
                final isError = d.severity == DiagnosticSeverity.error;
                return ListTile(
                  dense: true,
                  leading: Icon(
                    isError
                        ? Icons.error_outline
                        : Icons.warning_amber_outlined,
                    size: 16,
                    color: isError ? cs.error : cs.tertiary,
                  ),
                  title: Text(d.message,
                      style: TextStyle(color: cs.onSurface, fontSize: 12)),
                  subtitle: Text('Line ${d.range.start.line + 1}',
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 11)),
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: iconColor ?? cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(text,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
        ],
      ),
    );
  }
}
