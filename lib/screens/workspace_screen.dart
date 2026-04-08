import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_installer/app_installer.dart';
import 'package:build_runner_pkg/build_runner_pkg.dart'
    show BuildPlatform, supportedPlatforms;
import 'package:code_editor/code_editor.dart';
import 'package:dap_client/dap_client.dart';
import 'package:core/core.dart';
import 'package:fl_ide/screens/standalone_terminal_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:quill_code/quill_code.dart'
    show DiagnosticSeverity, QuillActionsMenu, SearchOptions;
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';
import 'package:ssh_pkg/ssh_pkg.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';

import '../app.dart' show editorThemeFromScheme, showThemedDialog;
import '../foreground_service.dart';
import 'ai_chat_drawer.dart';
import '../l10n/app_strings.dart';
import '../providers/extensions_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/ssh_lsp_bridge.dart';
import '../widgets/web_preview_overlay.dart';
import '../visual_editor/visual_editor_overlay.dart';
import 'settings_screen.dart' show SettingsScreen;

const _kDrawerWidth = 340.0;
const _kRailWidth = 64.0;
const _kSpecialChars = [
  '(', ')', '{', '}', '[', ']', ';', ':',
  '.', ',', '<', '>', '=', '!', '&', '|',
  '+', '-', '*', '/', r'\', '_', '"', "'",
  '#', '@', r'$', '%', '^', '~', '?', '\t',
];

// Init phases shown in the peek bar
enum _InitPhase { creatingProject, loadingProject, startingLsp, syncingDeps, ready }

// Shared liquid-glass shader settings used across AppBar, drawer, and bottom sheet.
const _kGlassSettings = OCLiquidGlassSettings(
  blurRadiusPx: 3.0,
  refractStrength: -0.06,
  distortFalloffPx: 18.0,
  specStrength: 25,
  specPower: 6.0,
  specWidth: 0.35,
  lightbandStrength: 0.18,
  lightbandWidthPx: 5.0,
);

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
  late final AnimationController _aiDrawerCtrl;
  late final Animation<double> _aiDrawerAnim;
  final _sheetKey = GlobalKey<_BottomSheetPanelState>();
  _InitPhase _initPhase = _InitPhase.loadingProject;
  bool _showWebPreview = false;
  String? _webPreviewUrl;
  OverlayEntry? _webPreviewEntry;

  // ── Sync banner (pub get / npm install / etc.) ─────────────────────────────
  bool _syncBannerVisible = false;
  String _syncCommand = '';
  String _syncTriggerPath = '';

  // Cached EditorProvider reference — safe to use in dispose()
  EditorProvider? _editorProvider;

  // ── Auto-save ──────────────────────────────────────────────────────────────
  Timer? _autoSaveTimer;

  // Cached provider reference — safe to use in dispose()
  DebugProvider? _debugProvider;

  // SSH LSP bridge — closed on dispose
  SshLspBridge? _sshLspBridge;

  @override
  void initState() {
    super.initState();
    _drawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _drawerAnim = CurvedAnimation(
      parent: _drawerCtrl,
      curve: Curves.easeInOut,
    );
    _aiDrawerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _aiDrawerAnim = CurvedAnimation(
      parent: _aiDrawerCtrl,
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

      // ── SSH wait ────────────────────────────────────────────────────────
      // Give the ChangeNotifierProxyProvider 300 ms to fire onSettingsReady()
      // and start connecting. This is unconditional and cheap.
      final ssh = context.read<SshProvider>();
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      // If auto-connect kicked in, wait for it to finish (up to 8 s).
      if (ssh.status == SshStatus.connecting) {
        final sshDone = Completer<void>();
        void onSsh() {
          if (ssh.status != SshStatus.connecting && !sshDone.isCompleted) {
            sshDone.complete();
          }
        }
        ssh.addListener(onSsh);
        try {
          await sshDone.future.timeout(const Duration(seconds: 8));
        } catch (_) {}
        ssh.removeListener(onSsh);
      }

      // Determine whether this project lives on the remote machine.
      // Guard: remoteProjectsPath must be non-empty — startsWith('') is always
      // true and would treat ALL local projects as remote.
      final isRemoteProject = ssh.isConnected &&
          ssh.config != null &&
          ssh.config!.remoteProjectsPath.isNotEmpty &&
          widget.project.path.startsWith(ssh.config!.remoteProjectsPath);

      // ── Phase 1b: load file tree ─────────────────────────────────────────
      final editor = context.read<EditorProvider>();
      if (isRemoteProject) {
        // Use SFTP for the remote project: listing + file read/write.
        await editor.loadProjectRemote(
          widget.project.path,
          (path) async {
            final entries = await ssh.listDirectory(path);
            return entries
                .map((e) => {
                      'name': e.name,
                      'path': e.path,
                      'isDirectory': e.isDirectory,
                    })
                .toList();
          },
          readFile: ssh.readFile,
          writeFile: ssh.writeFile,
        );
        // Remote files are opened on demand via SFTP — skip entry file open.
      } else {
        await editor.loadProject(widget.project.path);
        if (!mounted) return;

        // Open the default entry file for local projects.
        final loadedExt = context.read<ExtensionsProvider>().availableSdks
            .where((e) => e.sdk == widget.project.sdk.name)
            .firstOrNull;
        final loadedCfg = loadedExt?.sdkConfig ??
            SdkDefinition.forType(widget.project.sdk).sdkConfig;
        final entryFile = '${widget.project.path}/${loadedCfg.defaultEntryFile}';
        await editor.openFile(entryFile);
      }
      if (!mounted) return;

      // Start foreground service to prevent background kill.
      // Catch ServiceTimeoutException — the service may time out on first launch
      // (Android needs a moment to bind). Non-fatal: SSH keepalive still works
      // via WakeLock/WifiLock; the service is best-effort.
      // ignore: unawaited_futures
      _startForegroundService();

      // ── Phase 2: terminal ────────────────────────────────────────────────
      // Terminal (and cd into project dir) is started BEFORE LSP so that for
      // SSH projects the shell is already in the project directory when the
      // LSP server receives the initialize request.
      // Use SSH shell only for remote projects; local projects use PTY.
      final session = await context.read<TerminalProvider>().createSession(
        label: widget.project.name,
        workingDirectory: isRemoteProject ? null : widget.project.path,
        sshSetup: isRemoteProject
            ? (s) async {
                final sshSession = await ssh.startShell();
                final ctrl = StreamController<List<int>>();
                ctrl.stream.listen(
                    (bytes) => sshSession.stdin.add(Uint8List.fromList(bytes)));
                s.attachRemote(
                  remoteOutput: sshSession.stdout.cast<List<int>>(),
                  remoteInput: ctrl.sink,
                  doneFuture: sshSession.done,
                  onResize: (w, h) => sshSession.resizeTerminal(w, h),
                );
              }
            : null,
      );
      // For remote projects, cd into the project dir after the SSH shell is ready.
      // Local projects already start in workingDirectory — no cd needed.
      // A short settle delay is kept for local so the frame stabilises before
      // LSP init (and as a mounted-check opportunity after the createSession await).
      if (isRemoteProject) {
        final shellDelay = ssh.remoteIsWindows
            ? const Duration(milliseconds: 2500)
            : const Duration(milliseconds: 1200);
        await Future.delayed(shellDelay);
        if (!mounted) return;
        session.writeCommand('cd "${widget.project.path}"');
      } else {
        await Future.delayed(const Duration(milliseconds: 300));
        if (!mounted) return;
      }

      // ── Phase 3: LSP ──────────────────────────────────────────────────────
      // LSP starts after the terminal has cd'd so the workspace is fully active.
      setState(() => _initPhase = _InitPhase.startingLsp);
      final lspProv = context.read<LspProvider>();

      if (isRemoteProject) {
        // Start the LSP server on the remote machine and bridge it via
        // a local WebSocket server → QuillLspSocketConfig.
        final remoteCmd = lspProv.lspRemoteCommandFor(
            _sdkExtension(widget.project.sdk));
        if (remoteCmd != null) {
          try {
            final sshSession = await ssh.startProcess(remoteCmd);
            // Log stderr so we can see if the LSP process fails to start.
            sshSession.stderr
                .map((b) => utf8.decode(b, allowMalformed: true))
                .expand((s) => s.split('\n'))
                .where((l) => l.trim().isNotEmpty)
                .listen((line) => debugPrint('[LSP SSH stderr] $line'));
            _sshLspBridge = await SshLspBridge.start(
              remoteStdout: sshSession.stdout,
              remoteStdin: sshSession.stdin,
            );
            // Wait 600 ms — if the remote command exits immediately
            // (command not found, wrong PATH, etc.) the bridge marks itself
            // dead and we skip startForSocket entirely, avoiding the
            // "Connection refused" crash in QuillCodeEditor.
            await Future.delayed(const Duration(milliseconds: 600));
            if (!mounted) return;
            if (_sshLspBridge!.isAlive) {
              lspProv.startForSocket(
                _sshLspBridge!.wsUrl,
                _sdkExtension(widget.project.sdk),
                widget.project.path,
              );
              // Fallback: mark LSP ready after 30 s even if no diagnostics
              // arrive (e.g. project has zero errors → callback never fires).
              Future.delayed(const Duration(seconds: 30), () {
                if (mounted) context.read<LspProvider>().markReady();
              });
            } else {
              debugPrint('[LSP SSH] Remote LSP process exited immediately — skipping');
              _sshLspBridge!.close();
              _sshLspBridge = null;
              lspProv.stop();
            }
          } catch (e) {
            debugPrint('[LSP SSH] Failed to start: $e');
          }
        }
        // _initPhase → ready (the bottom-panel progress bar clears separately
        // when lspProv.markReady() is called from onDiagnosticsReceived or
        // the 30 s fallback above).
        setState(() => _initPhase = _InitPhase.ready);
      } else {
        // Local LSP
        final settings = context.read<SettingsProvider>();
        final loadedExt2 = context.read<ExtensionsProvider>().availableSdks
            .where((e) => e.sdk == widget.project.sdk.name)
            .firstOrNull;
        final loadedCfg2 = loadedExt2?.sdkConfig ??
            SdkDefinition.forType(widget.project.sdk).sdkConfig;
        await lspProv.startForExtension(
          loadedCfg2.defaultEntryFile.split('.').last,
          widget.project.path,
          customPaths: settings.lspPaths,
        );
        if (!mounted) return;

        if (lspProv.status == LspStatus.warming) {
          final activeCtrl = context.read<EditorProvider>().activeFile?.controller;
          if (activeCtrl is LspAwareController) {
            activeCtrl.onDiagnosticsReceived = () {
              lspProv.markReady();
              if (mounted) setState(() => _initPhase = _InitPhase.ready);
            };
          }
        } else {
          setState(() => _initPhase = _InitPhase.ready);
        }
      }

      // Show sync banner if the project has a dependency file (local only).
      final ext = context.read<ExtensionsProvider>().availableSdks
          .where((e) => e.sdk == widget.project.sdk.name)
          .firstOrNull;
      final sdkCfg = ext?.sdkConfig ??
          SdkDefinition.forType(widget.project.sdk).sdkConfig;
      if (!isRemoteProject &&
          sdkCfg.syncCommand.isNotEmpty &&
          sdkCfg.syncTriggerFile.isNotEmpty) {
        final triggerPath =
            '${widget.project.path}/${sdkCfg.syncTriggerFile}';
        if (await File(triggerPath).exists()) {
          if (mounted) {
            setState(() {
              _syncCommand = sdkCfg.syncCommand;
              _syncTriggerPath = triggerPath;
            });
          }
        }
      }

      // Auto-save every 30 seconds
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        context.read<EditorProvider>().saveActiveFile();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dbg = context.read<DebugProvider>();
    _debugProvider = dbg;
    dbg.removeListener(_onDebugChanged);
    dbg.addListener(_onDebugChanged);

    final editor = context.read<EditorProvider>();
    _editorProvider = editor;
    editor.removeListener(_onEditorChanged);
    editor.addListener(_onEditorChanged);
  }

  void _onEditorChanged() {
    if (!mounted) return;
    final saved = _editorProvider?.lastSavedPath;
    if (saved != null &&
        _syncTriggerPath.isNotEmpty &&
        saved == _syncTriggerPath &&
        !_syncBannerVisible) {
      setState(() => _syncBannerVisible = true);
    }

    // For SSH LSP (WebSocket) the entry file is never auto-opened, so
    // onDiagnosticsReceived can't be set in _init().  Wire it up here
    // whenever a new file is opened while LSP is still warming.
    final lsp = context.read<LspProvider>();
    if (lsp.status == LspStatus.warming) {
      final ctrl = _editorProvider?.activeFile?.controller;
      if (ctrl is LspAwareController && ctrl.onDiagnosticsReceived == null) {
        ctrl.onDiagnosticsReceived = () {
          lsp.markReady();
          if (mounted) setState(() => _initPhase = _InitPhase.ready);
        };
      }
    }
  }

  void _onDebugChanged() {
    if (!mounted) return;
    final dbg = context.read<DebugProvider>();
    final url = dbg.webServerUrl;
    if (url != null && !_showWebPreview) {
      _showPreview(url: url);
    } else if (url == null && _showWebPreview) {
      _hidePreview();
    }
  }

  void _showPreview({String? url}) {
    final mq = MediaQuery.of(context);
    final initialPos = Offset(16, mq.padding.top + kToolbarHeight + 3 + 10);
    _webPreviewEntry?.remove();
    final resolvedUrl = url ?? _webPreviewUrl ?? 'http://localhost:${DebugProvider.webServerPort}';
    // Re-inject DebugProvider so the overlay toolbar can access it.
    // OverlayEntry builders run in a context that is above the Provider tree.
    final debugProvider = context.read<DebugProvider>();
    _webPreviewEntry = OverlayEntry(
      builder: (_) => ChangeNotifierProvider<DebugProvider>.value(
        value: debugProvider,
        child: WebPreviewOverlay(
          url: resolvedUrl,
          onClose: _hidePreview,
          initialPos: initialPos,
        ),
      ),
    );
    Overlay.of(context).insert(_webPreviewEntry!);
    setState(() {
      _showWebPreview = true;
      if (url != null) _webPreviewUrl = url;
    });
  }

  void _hidePreview() {
    _webPreviewEntry?.remove();
    _webPreviewEntry = null;
    if (mounted) setState(() => _showWebPreview = false);
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    _webPreviewEntry?.remove();
    _webPreviewEntry = null;
    _debugProvider?.removeListener(_onDebugChanged);
    _editorProvider?.removeListener(_onEditorChanged);
    _drawerCtrl.dispose();
    _aiDrawerCtrl.dispose();
    _sshLspBridge?.close();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    _stopForegroundService();
    super.dispose();
  }

  Future<void> _startForegroundService() async {
    try {
      await FlutterForegroundTask.startService(
        serviceId: 256,
        notificationTitle: 'FL IDE',
        notificationText: widget.project.name,
        callback: fgServiceCallback,
      );
    } catch (_) {}
  }

  Future<void> _stopForegroundService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (_) {}
  }

  static String _sdkExtension(SdkType sdk) {
    switch (sdk) {
      case SdkType.flutter:
        return 'dart';
      case SdkType.nodejs:
      case SdkType.reactNative:
        return 'js';
      case SdkType.python:
        return 'py';
      case SdkType.androidSdk:
      case SdkType.swift:
        return 'dart'; // fallback — no LSP for these on remote
    }
  }

  void _runSync() {
    setState(() {
      _syncBannerVisible = false;
      _initPhase = _InitPhase.syncingDeps;
    });
    _sheetKey.currentState?.expandToMid();
    // The terminal session is always the first one created.
    final termProv = context.read<TerminalProvider>();
    final sessions = termProv.sessions;
    if (sessions.isNotEmpty) {
      sessions.first.writeCommand(_syncCommand);
    }
    // After a generous timeout revert the peek bar to ready regardless.
    Future.delayed(const Duration(seconds: 90), () {
      if (mounted && _initPhase == _InitPhase.syncingDeps) {
        setState(() => _initPhase = _InitPhase.ready);
      }
    });
  }

  void _closeDrawer()    => _drawerCtrl.reverse();
  void _closeAiDrawer()  => _aiDrawerCtrl.reverse();
  void _toggleDrawer() {
    if (_drawerCtrl.isCompleted) _drawerCtrl.reverse();
    else _drawerCtrl.forward();
  }
  void _toggleAiDrawer() {
    if (_aiDrawerCtrl.isCompleted) _aiDrawerCtrl.reverse();
    else _aiDrawerCtrl.forward();
  }

  void _expandBottomSheet() {
    _sheetKey.currentState?.expandToMid();
  }

  @override
  Widget build(BuildContext context) {
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 150;
    final liquidGlass = context.watch<SettingsProvider>().liquidGlass;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (_, __) {
        if (_aiDrawerCtrl.isCompleted) { _closeAiDrawer(); return; }
        if (_drawerCtrl.isCompleted) _closeDrawer();
      },
      child: Scaffold(
        // ── Performance: each drawer has its own AnimatedBuilder so they
        //    don't trigger each other's rebuilds. AiChatDrawer lives as the
        //    `child` of its builder — built ONCE, not reconstructed each frame.
        body: Stack(
          children: [
            // ── Main content + left drawer ─────────────────────────────────
            AnimatedBuilder(
              animation: _drawerAnim,
              child: _MainContent(
                project: widget.project,
                sheetKey: _sheetKey,
                keyboardVisible: keyboardVisible,
                liquidGlass: liquidGlass,
                initPhase: _initPhase,
                syncBannerVisible: _syncBannerVisible,
                syncCommand: _syncCommand,
                onSyncIgnore: () => setState(() => _syncBannerVisible = false),
                onSyncRun: _runSync,
              ),
              builder: (context, mainChild) {
                final cs    = Theme.of(context).colorScheme;
                final leftV = _drawerAnim.value;
                return Stack(
                  children: [
                    // Main content slides right when left drawer opens
                    Transform.translate(
                      offset: Offset(leftV * _kDrawerWidth, 0),
                      child: ColoredBox(
                        color: cs.surface,
                        child: SafeArea(
                          child: Column(
                            children: [
                              if (liquidGlass)
                                LiquidGlassLayer(
                                  child: LiquidGlass(
                                    shape: LiquidRoundedSuperellipse(borderRadius: 30),
                                    child: _WorkspaceAppBar(
                                      project: widget.project,
                                      drawerAnim: _drawerAnim,
                                      onMenuTap: _toggleDrawer,
                                      onAiTap: _toggleAiDrawer,
                                      liquidGlass: true,
                                      onShowWebPreview: () {
                                        final url = context.read<DebugProvider>().webServerUrl;
                                        _showPreview(url: url);
                                      },
                                    ),
                                  ),
                                )
                              else
                                _WorkspaceAppBar(
                                  project: widget.project,
                                  drawerAnim: _drawerAnim,
                                  onMenuTap: _toggleDrawer,
                                  onAiTap: _toggleAiDrawer,
                                  liquidGlass: false,
                                  onShowWebPreview: () {
                                    final url = context.read<DebugProvider>().webServerUrl;
                                    _showPreview(url: url);
                                  },
                                ),
                              Expanded(child: mainChild!),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Left drawer slides in from left
                    Positioned(
                      left: 0, top: 0, bottom: 0,
                      width: _kDrawerWidth,
                      child: Transform.translate(
                        offset: Offset((leftV - 1) * _kDrawerWidth, 0),
                        child: Builder(builder: (context) {
                          final pad = MediaQuery.of(context).padding;
                          final drawerContent = Padding(
                            padding: EdgeInsets.only(
                                top: pad.top, bottom: pad.bottom),
                            child: _DrawerContent(
                              project: widget.project,
                              onClose: _closeDrawer,
                              onTabChange: (i) {
                                _sheetKey.currentState?.selectToolTab(i);
                                _closeDrawer();
                                _expandBottomSheet();
                              },
                            ),
                          );
                          if (liquidGlass) {
                            return OCLiquidGlassGroup(
                              settings: _kGlassSettings,
                              child: OCLiquidGlass(
                                color: cs.surfaceContainerLow
                                    .withValues(alpha: 0.10),
                                borderRadius: 0,
                                child: drawerContent,
                              ),
                            );
                          }
                          return ColoredBox(
                              color: cs.surface, child: drawerContent);
                        }),
                      ),
                    ),

                    // Left scrim — tap to close left drawer
                    if (leftV > 0)
                      Positioned.fill(
                        left: _kDrawerWidth * leftV,
                        child: GestureDetector(
                          onTap: _closeDrawer,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                      ),
                  ],
                );
              },
            ),

            // ── Right drawer (AI chat — full-screen) ──────────────────────
            // Separate AnimatedBuilder: AiChatDrawer is the `child` so it is
            // built once and never reconstructed during the slide animation.
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _aiDrawerAnim,
                child: AiChatDrawer(
                  onClose: _closeAiDrawer,
                  project: widget.project,
                ),
                builder: (ctx, child) {
                  final v = _aiDrawerAnim.value;
                  if (v < 0.01) return const SizedBox.shrink();
                  return Transform.translate(
                    offset: Offset(
                        (1 - v) * MediaQuery.sizeOf(ctx).width, 0),
                    child: child,
                  );
                },
              ),
            ),
          ],
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
  final VoidCallback onAiTap;
  final VoidCallback onShowWebPreview;
  final bool liquidGlass;

  const _WorkspaceAppBar({
    required this.project,
    required this.drawerAnim,
    required this.onMenuTap,
    required this.onAiTap,
    required this.onShowWebPreview,
    required this.liquidGlass,
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

  Future<void> _startDebugSession(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    // Save (+ format) all open files before building.
    await context.read<EditorProvider>().saveAllFiles(format: settings.formatOnSave);
    if (!context.mounted) return;
    final platforms = supportedPlatforms(widget.project.sdk);
    final savedName = settings.debugPlatformFor(widget.project.sdk.name);
    final platform = savedName != null
        ? platforms.firstWhere((p) => p.name == savedName,
            orElse: () => platforms.first)
        : platforms.first;
    // Prefer DapConfig from installed JSON extension, fall back to SdkDefinition.
    final ext = context.read<ExtensionsProvider>().availableSdks
        .where((e) => e.sdk == widget.project.sdk.name)
        .firstOrNull;
    final dapConfig = ext?.dapConfig ??
        SdkDefinition.forType(widget.project.sdk).dapConfig;

    final ssh = context.read<SshProvider>();
    final isRemoteProject = ssh.isConnected &&
        ssh.config != null &&
        ssh.config!.remoteProjectsPath.isNotEmpty &&
        widget.project.path.startsWith(ssh.config!.remoteProjectsPath);

    if (isRemoteProject) {
      // Build the DAP adapter command for the remote machine.
      // adapterBinary + adapterArgs, e.g. "dart debug_adapter".
      final bin = dapConfig.adapterBinary.isNotEmpty
          ? dapConfig.adapterBinary
          : 'dart';
      final args = dapConfig.adapterArgs.isNotEmpty
          ? dapConfig.adapterArgs
          : ['debug_adapter'];
      final adapterCmd = [bin, ...args].join(' ');
      try {
        final sshSession = await ssh.startProcess(adapterCmd);
        if (!context.mounted) return;
        context.read<DebugProvider>().startSessionRemote(
          widget.project,
          remoteStdout: sshSession.stdout,
          remoteStdin: sshSession.stdin,
          platform: platform.name,
          dapConfig: dapConfig,
        );
      } catch (e) {
        debugPrint('[DAP SSH] Failed to start remote adapter: $e');
      }
      return;
    }

    context.read<DebugProvider>().startSession(
          widget.project,
          platform: platform.name,
          dapConfig: dapConfig,
        );
  }

  void _showWebPreview(BuildContext context) {
    widget.onShowWebPreview();
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
      color: widget.liquidGlass ? Colors.transparent : cs.surface,
      child: SizedBox(
        height: kToolbarHeight + 3,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _searchMode
                    ? _buildSearchBar(cs)
                    : _buildNormalBar(cs),
              ),
            ),
            Consumer<DebugProvider>(
              builder: (context, dbg, _) =>
                  (dbg.status == DebugStatus.starting || dbg.isBuilding)
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
        // ── Run / Stop DAP button ──────────────────────────────────
        Consumer<DebugProvider>(
          builder: (context, dbg, _) {
            if (dbg.isActive) {
              return IconButton(
                icon: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: cs.error, width: 2),
                  ),
                  child: Icon(Icons.stop, color: cs.error, size: 11),
                ),
                onPressed: () => dbg.stopSession(),
                tooltip: 'Stop debug session',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              );
            }
            return IconButton(
              icon: Icon(Icons.play_arrow_rounded, color: cs.primary, size: 24),
              onPressed: () => _startDebugSession(context),
              tooltip: 'Run & Debug',
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            );
          },
        ),
        // ── Web preview button (only when DAP is running on web) ───
        Consumer<DebugProvider>(
          builder: (context, dbg, _) {
            if (!dbg.isActive) return const SizedBox.shrink();
            final settings = context.read<SettingsProvider>();
            final pName = settings.debugPlatformFor(widget.project.sdk.name)
                ?? supportedPlatforms(widget.project.sdk).first.name;
            if (pName != BuildPlatform.web.name) return const SizedBox.shrink();
            return IconButton(
              icon: Icon(Icons.web_rounded, color: cs.primary, size: 22),
              onPressed: () => _showWebPreview(context),
              tooltip: 'Web Preview',
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            );
          },
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
                      editorThemeFromScheme(Theme.of(context).colorScheme);
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
        // ── AI chat ───────────────────────────────────────────────
        IconButton(
          icon: Icon(Icons.auto_awesome_rounded, color: cs.onSurface, size: 21),
          onPressed: widget.onAiTap,
          tooltip: 'Chat IA',
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
            final settings = context.read<SettingsProvider>();
            switch (val) {
              case 'undo':
                editor.undo();
              case 'redo':
                editor.redo();
              case 'save':
                editor.saveActiveFile(format: settings.formatOnSave);
              case 'sync':
                editor.loadProject(widget.project.path);
              case 'search':
                _enterSearch();
              case 'commands':
                final ctrl = editor.activeFile?.controller;
                if (ctrl == null) return;
                final theme =
                    context.read<ExtensionsProvider>().activeEditorTheme ??
                        editorThemeFromScheme(Theme.of(context).colorScheme);
                QuillActionsMenu.show(context, ctrl, theme);
              case 'hot_reload':
                context.read<DebugProvider>().hotReload();
              case 'hot_restart':
                context.read<DebugProvider>().restart();
              case 'visual_editor':
                openVisualEditor(context);
              case 'close':
                _confirmCloseProject(context);
            }
          },
          itemBuilder: (ctx) {
            final s = AppStrings.of(ctx);
            final dbg = context.read<DebugProvider>();
            return [
              PopupMenuItem(
                value: 'undo',
                height: 40,
                child: _PopupItem(icon: Icons.undo_rounded, label: s.wsUndo),
              ),
              PopupMenuItem(
                value: 'redo',
                height: 40,
                child: _PopupItem(icon: Icons.redo_rounded, label: s.wsRedo),
              ),
              PopupMenuItem(
                value: 'save',
                height: 40,
                child: _PopupItem(icon: Icons.save_outlined, label: s.save),
              ),
              PopupMenuItem(
                value: 'sync',
                height: 40,
                child: _PopupItem(
                    icon: Icons.sync_rounded, label: s.wsSyncProject),
              ),
              if (canUndo)
                PopupMenuItem(
                  value: 'search',
                  height: 40,
                  child: _PopupItem(
                      icon: Icons.search_rounded, label: s.wsSearchInFile),
                ),
              if (canRedo)
                PopupMenuItem(
                  value: 'commands',
                  height: 40,
                  child: _PopupItem(
                      icon: Icons.terminal_outlined, label: s.wsCommands),
                ),
              if (dbg.isRunning)
                PopupMenuItem(
                  value: 'hot_reload',
                  height: 40,
                  child: _PopupItem(
                      icon: Icons.electric_bolt_rounded, label: s.wsHotReload),
                ),
              if (dbg.isActive)
                PopupMenuItem(
                  value: 'hot_restart',
                  height: 40,
                  child: _PopupItem(
                      icon: Icons.restart_alt_rounded, label: s.wsHotRestart),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'visual_editor',
                height: 40,
                child: _PopupItem(
                    icon: Icons.auto_awesome_outlined,
                    label: 'Visual Editor'),
              ),
              PopupMenuItem(
                value: 'close',
                height: 40,
                child: _PopupItem(
                    icon: Icons.close,
                    label: s.wsCloseProject,
                    isDestructive: true),
              ),
            ];
          },
        ),
        const SizedBox(width: 2),
      ],
    );
  }
}

Future<void> _confirmCloseProject(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final confirmed = await showThemedDialog<bool>(
    context: context,
    builder: (ctx) {
      final ss = AppStrings.of(ctx);
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(ss.wsCloseProjectQ),
        content: Text(ss.wsCloseProjectBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ss.no, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ss.wsCloseYes),
          ),
        ],
      );
    },
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

class _MainContent extends StatefulWidget {
  final Project project;
  final GlobalKey<_BottomSheetPanelState> sheetKey;
  final bool keyboardVisible;
  final bool liquidGlass;
  final _InitPhase initPhase;
  final bool syncBannerVisible;
  final String syncCommand;
  final VoidCallback onSyncIgnore;
  final VoidCallback onSyncRun;

  const _MainContent({
    required this.project,
    required this.sheetKey,
    required this.keyboardVisible,
    required this.liquidGlass,
    required this.initPhase,
    required this.syncBannerVisible,
    required this.syncCommand,
    required this.onSyncIgnore,
    required this.onSyncRun,
  });

  @override
  State<_MainContent> createState() => _MainContentState();
}

class _MainContentState extends State<_MainContent> {
  final FocusNode _mainEditorFocusNode = FocusNode();
  bool _mainEditorFocused = false;

  @override
  void initState() {
    super.initState();
    _mainEditorFocusNode.addListener(_onMainEditorFocusChange);
  }

  void _onMainEditorFocusChange() {
    final focused = _mainEditorFocusNode.hasFocus;
    if (focused != _mainEditorFocused) {
      setState(() => _mainEditorFocused = focused);
    }
  }

  @override
  void dispose() {
    _mainEditorFocusNode.removeListener(_onMainEditorFocusChange);
    _mainEditorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final liquidGlass = widget.liquidGlass;
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack = Stack(
          children: [
            // ── Editor + overlay + bottom sheet (column) ─────────────────
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      bottom: _BottomSheetPanelState._kPeekBarH,
                    ),
                    child: Focus(
                      focusNode: _mainEditorFocusNode,
                      canRequestFocus: false,
                      skipTraversal: true,
                      child: EditorArea(
                        editorTheme: context.watch<ExtensionsProvider>().activeEditorTheme ??
                            editorThemeFromScheme(Theme.of(context).colorScheme),
                        showSymbolBar: false,
                        fontSize: settings.fontSize,
                        fontFamily: settings.fontFamily,
                        configureProps: settings.applyToProps,
                      ),
                    ),
                  ),
                ),
                // VS Code-style debug execution overlay
                const _DebugExecutionOverlay(),
              ],
            ),
            // ── Bottom sheet overlaid on top (draggable) ─────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _BottomSheetPanel(
                key: widget.sheetKey,
                availableHeight: constraints.maxHeight,
                project: widget.project,
                keyboardVisible: widget.keyboardVisible && _mainEditorFocused,
                liquidGlass: liquidGlass,
                initPhase: widget.initPhase,
              ),
            ),
          // ── Sync banner: anchored just above the peek bar ─────────────
          Positioned(
            left: 0,
            right: 0,
            bottom: _BottomSheetPanelState._kPeek,
            child: AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              alignment: Alignment.bottomCenter,
              child: widget.syncBannerVisible
                  ? _SyncBanner(
                      command: widget.syncCommand,
                      onIgnore: widget.onSyncIgnore,
                      onRun: widget.onSyncRun,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ],
        );
        // Wrap the whole stack in OCLiquidGlassGroup so that OCLiquidGlass
        // descendants (bottom sheet) can see the editor pixels behind them.
        if (liquidGlass) {
          return OCLiquidGlassGroup(settings: _kGlassSettings, child: stack);
        }
        return stack;
      },
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
        color: cs.surface,
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
              icon: Icons.bug_report_outlined,
              tooltip: 'Debug Output',
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
              onTap: () => onTabChange(4),
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
  final bool keyboardVisible;
  final bool liquidGlass;
  final _InitPhase initPhase;

  const _BottomSheetPanel({
    super.key,
    required this.availableHeight,
    required this.project,
    required this.keyboardVisible,
    required this.liquidGlass,
    required this.initPhase,
  });

  @override
  State<_BottomSheetPanel> createState() => _BottomSheetPanelState();
}

class _BottomSheetPanelState extends State<_BottomSheetPanel>
    with TickerProviderStateMixin {
  static const double _kPeek = 60.0;
  static const double _kMid = 400.0;
  static const double _kPeekBarH = 64.0;
  static const int _kToolCount = 5;

  double _height = _kPeek;
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  // Combined tab controller: [file tabs...] + [TERMINAL, PROBLEMS, VARIABLES, CALL STACK, OUTPUT]
  late TabController _combinedTabCtrl;
  int _fileTabCount = 0;
  EditorProvider? _editorProv;

  @override
  void initState() {
    super.initState();
    _combinedTabCtrl = TabController(length: _kToolCount, vsync: this);
    _combinedTabCtrl.addListener(_onTabChanged);
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _animCtrl.addListener(() => setState(() => _height = _anim.value));
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ep = context.read<EditorProvider>();
    if (_editorProv != ep) {
      _editorProv?.removeListener(_onEditorChanged);
      _editorProv = ep;
      ep.addListener(_onEditorChanged);
    }
  }

  void _onEditorChanged() {
    if (!mounted) return;
    _syncFromEditor(_editorProv!);
  }

  /// Keeps [_combinedTabCtrl] in sync when bottom-panel files change.
  void _syncFromEditor(EditorProvider ep) {
    final bf = ep.bottomPanelFiles;
    final total = bf.length + _kToolCount;

    if (_combinedTabCtrl.length != total) {
      // File count changed — rebuild controller preserving tool-tab selection.
      final oldIdx = _combinedTabCtrl.index;
      final oldFileCount = _fileTabCount;
      int newIdx;
      if (oldIdx >= oldFileCount) {
        // Was on a tool tab — keep same tool tab with new offset.
        newIdx = bf.length + (oldIdx - oldFileCount);
      } else if (ep.activeFile?.inBottomPanel == true) {
        // Active file is a bottom-panel file — jump to its tab.
        final i = bf.indexOf(ep.activeFile!);
        newIdx = i >= 0 ? i : 0;
      } else {
        newIdx = bf.length; // default to TERMINAL
      }
      newIdx = newIdx.clamp(0, total - 1);

      final old = _combinedTabCtrl;
      _combinedTabCtrl = TabController(length: total, vsync: this, initialIndex: newIdx);
      _combinedTabCtrl.addListener(_onTabChanged);
      _fileTabCount = bf.length;
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } else if (ep.activeFile?.inBottomPanel == true) {
      // Length unchanged but active file may have switched — sync index.
      final i = bf.indexOf(ep.activeFile!);
      if (i >= 0 && _combinedTabCtrl.index != i) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _combinedTabCtrl.index != i) {
            setState(() => _combinedTabCtrl.index = i);
          }
        });
      }
    }
  }

  /// Called by the drawer rail to jump to a specific tool tab.
  void selectToolTab(int toolIndex) {
    final i = (_fileTabCount + toolIndex).clamp(0, _combinedTabCtrl.length - 1);
    setState(() => _combinedTabCtrl.index = i);
  }

  @override
  void didUpdateWidget(_BottomSheetPanel old) {
    super.didUpdateWidget(old);
    if (widget.availableHeight == old.availableHeight) return;
    // Was fully expanded before the resize (e.g. keyboard opened/closed).
    final wasAtFull = _height >= old.availableHeight - 1;
    if (wasAtFull) {
      // Snap to the new full height so stage-3 is preserved.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snapTo(widget.availableHeight);
      });
    } else if (_height > widget.availableHeight) {
      setState(() => _height = widget.availableHeight);
    }
  }

  @override
  void dispose() {
    _editorProv?.removeListener(_onEditorChanged);
    _combinedTabCtrl.removeListener(_onTabChanged);
    _combinedTabCtrl.dispose();
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
        if (idx != -1) editor.moveToPanel(idx, bottom: true, atFirst: true);
      },
      builder: (dragCtx, candidates, _) {
        final isDragOver = candidates.isNotEmpty;
        return Consumer<EditorProvider>(
          builder: (ctx, editor, _) {
            final bf = editor.bottomPanelFiles;
            final tabIdx = _combinedTabCtrl.index;
            final isFileTab = tabIdx < bf.length;
            final panelColor = isDragOver
                ? cs.primaryContainer.withValues(alpha: 0.15)
                : cs.surface;
            final panelContent = Column(
                    children: [
                      // ── Draggable header ─────────────────────────────
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragUpdate: _onDragUpdate,
                        onVerticalDragEnd: _onDragEnd,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Divider(height: 1, thickness: 1, color: cs.outlineVariant),
                            // LSP / build progress indicator
                            Consumer2<LspProvider, DebugProvider>(
                              builder: (c, lsp, dbg, _) {
                                final loading = lsp.status == LspStatus.starting ||
                                    lsp.status == LspStatus.warming ||
                                    dbg.status == DebugStatus.starting ||
                                    dbg.isBuilding;
                                return loading
                                    ? LinearProgressIndicator(
                                        minHeight: 2,
                                        backgroundColor: cs.outlineVariant,
                                      )
                                    : const SizedBox.shrink();
                              },
                            ),
                            // Peek bar / special chars bar (animated switch)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              child: widget.keyboardVisible
                                  ? const _SpecialCharsBar()
                                  : Builder(builder: (context) {
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
                            ),
                            // ── Single unified tab bar ──────────────────
                            ColoredBox(
                              color: cs.surface,
                              child: TabBar(
                                controller: _combinedTabCtrl,
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
                                onTap: (i) {
                                  if (i < bf.length) {
                                    final gIdx = editor.openFiles.indexOf(bf[i]);
                                    if (gIdx != -1) editor.switchTo(gIdx);
                                  }
                                },
                                tabs: [
                                  // File tabs (dynamic)
                                  for (final f in bf)
                                    Tab(
                                      height: 40,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(f.name),
                                          const SizedBox(width: 6),
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              final gIdx = editor.openFiles.indexOf(f);
                                              if (gIdx != -1) editor.closeFile(gIdx);
                                            },
                                            child: Icon(Icons.close_rounded,
                                                size: 12,
                                                color: cs.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                    ),
                                  // Fixed tool tabs
                                  const Tab(text: 'TERMINAL', height: 40),
                                  const Tab(text: 'PROBLEMS', height: 40),
                                  const Tab(text: 'VARIABLES', height: 40),
                                  const Tab(text: 'CALL STACK', height: 40),
                                  const Tab(text: 'OUTPUT', height: 40),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: cs.outlineVariant),
                      // ── Content area ────────────────────────────────
                      Expanded(
                        child: isFileTab
                            ? Consumer2<ExtensionsProvider, SettingsProvider>(
                                builder: (c, ext, sett, _) => EditorArea(
                                  editorTheme: ext.activeEditorTheme ??
                                      editorThemeFromScheme(Theme.of(c).colorScheme),
                                  showSymbolBar: false,
                                  fontSize: sett.fontSize,
                                  fontFamily: sett.fontFamily,
                                  configureProps: sett.applyToProps,
                                  showTabBar: false,
                                  forBottomPanel: true,
                                ),
                              )
                            : IndexedStack(
                                index: (tabIdx - bf.length).clamp(0, _kToolCount - 1),
                                children: [
                                  TerminalTabs(
                                    initialWorkDir: widget.project.path,
                                    autoStart: false,
                                  ),
                                  _ProblemsPanel(),
                                  const DebugVariablesPanel(),
                                  const DebugCallStackPanel(),
                                  const DebugOutputPanel(),
                                ],
                              ),
                      ),
                    ],
                  );  // panelContent Column
            return SizedBox(
              height: _height,
              child: widget.liquidGlass
                  ? OCLiquidGlass(
                      height: _height,
                      color: cs.surface.withValues(alpha: 0.08),
                      borderRadius: 16.0,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        child: panelContent,
                      ),
                    )
                  : ClipRect(
                      child: Material(
                        color: panelColor,
                        child: panelContent,
                      ),
                    ),
            );
          },
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
      case _InitPhase.syncingDeps:
        label = s.peekSyncingDeps;
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
          const SizedBox(height: 3),
          Text(
            showProgress ? '...' : s.peekSwipeUp,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ── Sync-dependencies banner (slides up from TabBar into code area) ──────────

class _SyncBanner extends StatelessWidget {
  final String command;
  final VoidCallback onIgnore;
  final VoidCallback onRun;

  const _SyncBanner({
    required this.command,
    required this.onIgnore,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    return Material(
      color: cs.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.download_rounded,
                size: 18, color: cs.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.syncBannerMsg(command),
                style: TextStyle(
                    color: cs.onPrimaryContainer, fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: onIgnore,
              style: TextButton.styleFrom(
                  foregroundColor: cs.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: Text(s.syncBannerIgnore),
            ),
            FilledButton(
              onPressed: onRun,
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 32),
              ),
              child: Text(s.syncBannerRun),
            ),
          ],
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

// ── VS Code-style debug execution overlay ─────────────────────────────────────
//
// Appears at the bottom of the editor (above the bottom sheet) when a DAP
// session is active. Shows status, current stopped location, and quick actions.

class _DebugExecutionOverlay extends StatelessWidget {
  const _DebugExecutionOverlay();

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) {
        if (!dbg.isActive) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final paused = dbg.isPaused;

        // Status colour: orange when paused, green when running
        final statusColor = paused ? Colors.orange : Colors.green;

        String statusText;
        if (paused && dbg.stoppedFile != null && dbg.stoppedLine != null) {
          final fileName = dbg.stoppedFile!.split('/').last;
          statusText = 'Paused at $fileName:${dbg.stoppedLine}';
        } else if (paused) {
          statusText = 'Paused — ${dbg.stopReason ?? 'breakpoint'}';
        } else if (dbg.status == DebugStatus.starting) {
          statusText = 'Starting debug session…';
        } else {
          statusText = 'Running';
        }

        return Material(
          elevation: 4,
          color: cs.surfaceContainerHighest,
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: statusColor, width: 2),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                // Status dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.bug_report_rounded,
                    size: 13, color: cs.primary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.onSurface,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Quick actions
                _OverlayBtn(
                  icon: Icons.play_arrow_rounded,
                  tooltip: 'Continue',
                  enabled: paused,
                  color: Colors.green,
                  onTap: () => dbg.continueExec(),
                ),
                _OverlayBtn(
                  icon: Icons.pause_rounded,
                  tooltip: 'Pause',
                  enabled: dbg.isRunning,
                  onTap: () => dbg.pause(),
                ),
                _OverlayBtn(
                  icon: Icons.redo_rounded,
                  tooltip: 'Step Over',
                  enabled: paused,
                  onTap: () => dbg.stepOver(),
                ),
                _OverlayBtn(
                  icon: Icons.south_rounded,
                  tooltip: 'Step In',
                  enabled: paused,
                  onTap: () => dbg.stepIn(),
                ),
                _OverlayBtn(
                  icon: Icons.north_rounded,
                  tooltip: 'Step Out',
                  enabled: paused,
                  onTap: () => dbg.stepOut(),
                ),
                _OverlayBtn(
                  icon: Icons.electric_bolt_rounded,
                  tooltip: 'Hot Reload',
                  enabled: dbg.isRunning,
                  color: Colors.orange,
                  onTap: () => dbg.hotReload(),
                ),
                _OverlayBtn(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Restart',
                  enabled: paused || dbg.isRunning,
                  onTap: () => dbg.restart(),
                ),
                _OverlayBtn(
                  icon: Icons.stop_rounded,
                  tooltip: 'Stop',
                  enabled: true,
                  color: cs.error,
                  onTap: () => dbg.stopSession(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _OverlayBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Color? color;
  final VoidCallback onTap;

  const _OverlayBtn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? c : c.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
  }
}
