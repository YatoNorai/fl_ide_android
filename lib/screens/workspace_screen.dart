import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_installer/app_installer.dart';
import 'package:build_runner_pkg/build_runner_pkg.dart'
    show BuildPlatform, BuildProvider, LogBridgeInjector, LogcatProvider, LogLevel, supportedPlatforms;
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
    show CharPosition, DiagnosticSeverity, LspDiagnostic, QuillActionsMenu, QuillCodeController, SearchOptions;
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
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _drawerCtrl;
  late final Animation<double> _drawerAnim;
  late final AnimationController _aiDrawerCtrl;
  late final Animation<double> _aiDrawerAnim;
  final _sheetKey = GlobalKey<_BottomSheetPanelState>();
  _InitPhase _initPhase = _InitPhase.loadingProject;
  bool _showWebPreview = false;
  String? _webPreviewUrl;
  OverlayEntry? _webPreviewEntry;
  /// Shared between the WebPreview bubble and the DAP execution overlay so
  /// they can avoid overlapping when both are docked to the same edge.
  final _snapCoordinator = SnapCoordinator();

  // ── Sync banner (pub get / npm install / etc.) ─────────────────────────────
  bool _syncBannerVisible = false;
  String _syncCommand = '';
  String _syncTriggerPath = '';
  // Snapshot of the dependency section taken when the project loads.
  // The banner is shown only when a save changes this section.
  String _depSectionSnapshot = '';

  // Cached EditorProvider reference — safe to use in dispose()
  EditorProvider? _editorProvider;

  // ── Auto-save ──────────────────────────────────────────────────────────────
  Timer? _autoSaveTimer;

  // Cached provider reference — safe to use in dispose()
  DebugProvider? _debugProvider;

  // SSH LSP bridge — closed on dispose
  SshLspBridge? _sshLspBridge;

  // Track the last APK for which we showed the install dialog (avoid duplicates)
  String? _lastShownApk;

  // APK poll timer — detects APKs built via terminal (flutter build apk, etc.)
  Timer? _apkPollTimer;
  // Modification time of the last known APK — used to detect rebuilds
  DateTime? _lastApkMtime;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
        await _openEntryFile(editor, widget.project.path, loadedCfg);
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
        session.writeCommand('cd "${widget.project.path}"');
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
        // Local LSP — derive language from the file that actually opened,
        // falling back to the SDK extension (e.g. tsx for React Native).
        // This handles cases where App.tsx doesn't exist but app/index.js does.
        final settings = context.read<SettingsProvider>();
        final openedExt = context.read<EditorProvider>().activeFile?.extension;
        final lspExt = (openedExt != null && openedExt.isNotEmpty)
            ? openedExt
            : _sdkExtension(widget.project.sdk);
        _lspStartedExt = lspExt; // prevent auto-restart for this extension
        await lspProv.startForExtension(
          lspExt,
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

          // Fallback: JVM-based LSPs may never send diagnostics for clean
          // files, so the loading spinner would never clear.  Mark ready
          // slightly after the server's initialize timeout so a successful
          // init on a zero-error file still dismisses the spinner.
          final isJvmLsp = const {'java', 'kt', 'kotlin', 'xml'}
              .contains(lspExt.toLowerCase());
          if (isJvmLsp) {
            final fallbackSecs =
                const {'java', 'kt', 'kotlin'}.contains(lspExt.toLowerCase())
                    ? 130   // 10 s buffer over the 120 s initialize timeout
                    : 35;  // 5 s buffer over the 30 s XML timeout
            Future.delayed(Duration(seconds: fallbackSecs), () {
              if (!mounted) return;
              context.read<LspProvider>().markReady();
              setState(() => _initPhase = _InitPhase.ready);
            });
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
          final snapshot = _depSection(
            await File(triggerPath).readAsString(),
            widget.project.sdk,
          );
          if (mounted) {
            setState(() {
              _syncCommand = sdkCfg.syncCommand;
              _syncTriggerPath = triggerPath;
              _depSectionSnapshot = snapshot;
            });
          }
        }
      }

      // Auto-save every 30 seconds
      _autoSaveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        context.read<EditorProvider>().saveActiveFile();
      });

      // Pre-seed APK state so that an APK that already existed when the project
      // was opened does NOT immediately trigger the install dialog.  The dialog
      // should only appear after a fresh build or when the user taps the APK
      // in the file tree.
      final existingApk = LogcatProvider.findLatestApk(widget.project.path);
      if (existingApk != null) {
        _lastShownApk = existingApk;
        _lastApkMtime = File(existingApk).lastModifiedSync();
      }

      // APK poll — detect APKs built via terminal (flutter build apk, etc.)
      // Scans output directories every 4 s; triggers install dialog when the
      // modification time of the latest APK changes.
      _apkPollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        if (!mounted) return;
        _checkForNewTerminalApk();
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

  // Extension of the file the LSP was last started for — used to detect
  // when the user switches to a different language and we need to restart.
  String _lspStartedExt = '';

  void _onEditorChanged() {
    if (!mounted) return;
    final saved = _editorProvider?.lastSavedPath;
    if (saved != null &&
        _syncTriggerPath.isNotEmpty &&
        saved == _syncTriggerPath &&
        !_syncBannerVisible) {
      // Only show when the trigger file is open in a tab (must be open to save).
      final isOpen = _editorProvider?.openFiles.any((f) => f.path == saved) ?? false;
      if (isOpen) {
        final file = File(saved);
        if (file.existsSync()) {
          final current = _depSection(file.readAsStringSync(), widget.project.sdk);
          if (current != _depSectionSnapshot) {
            setState(() => _syncBannerVisible = true);
          }
        }
      }
    }

    final lsp = context.read<LspProvider>();

    // For SSH LSP (WebSocket) the entry file is never auto-opened, so
    // onDiagnosticsReceived can't be set in _init().  Wire it up here
    // whenever a new file is opened while LSP is still warming.
    if (lsp.status == LspStatus.warming) {
      final ctrl = _editorProvider?.activeFile?.controller;
      if (ctrl is LspAwareController && ctrl.onDiagnosticsReceived == null) {
        ctrl.onDiagnosticsReceived = () {
          lsp.markReady();
          if (mounted) setState(() => _initPhase = _InitPhase.ready);
        };
      }
    }

    // Auto-restart LSP when the user opens a file whose language has no running
    // LSP yet (e.g. entry file was .xml/.kts but user navigates to .kt/.java).
    // Only restart if: LSP is stopped AND the new extension differs from the
    // last one we tried (prevents a restart loop on rapid file switches).
    final newExt = _editorProvider?.activeFile?.extension ?? '';
    if (newExt.isNotEmpty &&
        newExt != _lspStartedExt &&
        lsp.status == LspStatus.stopped) {
      _lspStartedExt = newExt;
      final settings = context.read<SettingsProvider>();
      lsp.startForExtension(
        newExt,
        widget.project.path,
        customPaths: settings.lspPaths,
      );
    }
  }

  void _onDebugChanged() {
    if (!mounted) return;
    final dbg = context.read<DebugProvider>();

    // Open DEBUG CONSOLE tab and expand the sheet when a build/debug session starts.
    if (dbg.isBuilding || dbg.status == DebugStatus.starting) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _sheetKey.currentState?.selectToolTab(4); // 4 = DEBUG CONSOLE
        _sheetKey.currentState?.expandToMid();
      });
    }

    // Show APK install dialog after a successful build
    final apk = dbg.lastBuiltApk;
    if (apk != null && apk != _lastShownApk) {
      _lastShownApk = apk;
      // Refresh tree so the APK appears in the file browser
      context.read<EditorProvider>().refreshTree();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showApkInstallDialog(apk);
      });
    }

    final url = dbg.webServerUrl;
    if (url != null && !_showWebPreview) {
      _showPreview(url: url);
    } else if (url == null && _showWebPreview) {
      _hidePreview();
    }
  }

  void _showApkInstallDialog(String apkPath) {
    // Detect package name BEFORE launching the system installer so we can start
    // logcat right away — the app may launch seconds after install completes.
    final packageName = LogcatProvider.detectPackageName(widget.project.path);

    context.read<AppInstallerProvider>().installApk(apkPath).then((_) {
      if (!mounted) return;
      final installer = context.read<AppInstallerProvider>();
      if (installer.installStatus == InstallStatus.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(installer.installError ?? 'Failed to open installer')),
        );
        return;
      }

      // Start logcat for the installed app (waits for the app PID to appear).
      if (packageName != null) {
        context.read<LogcatProvider>().start(packageName);
        // Jump to LOGCAT tab (index 6) and expand the sheet.
        _sheetKey.currentState?.selectToolTab(6);
        _sheetKey.currentState?.expandToMid();
      }
    });
  }

  /// Polls APK output directories to detect APKs built via terminal commands
  /// (e.g. `flutter build apk`, `./gradlew assembleDebug`).
  /// Triggers the install + logcat flow when a new or updated APK is found.
  void _checkForNewTerminalApk() {
    final apkPath = LogcatProvider.findLatestApk(widget.project.path);
    if (apkPath == null) return;

    // Skip if this APK was already shown (same path + same mtime).
    final mtime = File(apkPath).lastModifiedSync();
    if (apkPath == _lastShownApk && _lastApkMtime == mtime) return;

    // Skip APKs that were already handled by the DebugProvider build flow.
    if (apkPath == _lastShownApk) {
      _lastApkMtime = mtime;
      return;
    }

    _lastShownApk  = apkPath;
    _lastApkMtime  = mtime;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _showApkInstallDialog(apkPath);
    });
  }

  void _showPreview({String? url}) {
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
          navigatorContext: context,
          coordinator: _snapCoordinator,
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
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // When the IDE goes to the background while a debug/build session is active,
    // the foreground service keeps the process alive so SSH keepalive and LSP
    // connections survive screen-off.  No action needed here beyond logging.
    debugPrint('[WorkspaceScreen] lifecycle → $state');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoSaveTimer?.cancel();
    _apkPollTimer?.cancel();
    _webPreviewEntry?.remove();
    _webPreviewEntry = null;
    _snapCoordinator.dispose();
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
      debugPrint('[FgService] started for ${widget.project.name}');
    } catch (e) {
      debugPrint('[FgService] start failed: $e');
    }
  }

  Future<void> _stopForegroundService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
        debugPrint('[FgService] stopped');
      }
    } catch (e) {
      debugPrint('[FgService] stop failed: $e');
    }
  }

  /// Tries to open the project's default entry file, falling back to a list of
  /// common alternatives. Handles Expo Router (app/index.tsx), classic Expo
  /// (App.tsx / App.js), plain React Native (index.js), Node (index.js), etc.
  static Future<void> _openEntryFile(
      EditorProvider editor, String projectPath, SdkConfig cfg) async {
    // Primary candidate from SDK config
    final primary = '$projectPath/${cfg.defaultEntryFile}';
    // Build a list of fallbacks without duplicates
    final candidates = <String>[
      primary,
      '$projectPath/app/index.tsx',
      '$projectPath/app/index.ts',
      '$projectPath/app/index.js',
      '$projectPath/App.tsx',
      '$projectPath/App.ts',
      '$projectPath/App.js',
      '$projectPath/index.tsx',
      '$projectPath/index.ts',
      '$projectPath/index.js',
      '$projectPath/src/App.tsx',
      '$projectPath/src/App.js',
      '$projectPath/src/index.tsx',
      '$projectPath/src/index.js',
      '$projectPath/main.dart',
      '$projectPath/Sources/main.swift',
      '$projectPath/app/src/main/java/MainActivity.kt',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) {
        await editor.openFile(path);
        return;
      }
    }
    // Android native: package directory varies — scan kotlin/java source trees
    // for the first .kt or .java file (e.g. app/src/main/kotlin/com/…/MainActivity.kt).
    for (final srcDir in [
      '$projectPath/app/src/main/kotlin',
      '$projectPath/app/src/main/java',
    ]) {
      final dir = Directory(srcDir);
      if (!dir.existsSync()) continue;
      try {
        final files = dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.kt') || f.path.endsWith('.java'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        if (files.isNotEmpty) {
          await editor.openFile(files.first.path);
          return;
        }
      } catch (_) {}
    }
    // Last resort: open the first non-hidden file at the project root
    try {
      final dir = Directory(projectPath);
      final entries = dir.listSync(recursive: false)
          .whereType<File>()
          .where((f) => !f.path.split('/').last.startsWith('.'))
          .toList();
      if (entries.isNotEmpty) await editor.openFile(entries.first.path);
    } catch (_) {}
  }

  static String _sdkExtension(SdkType sdk) {
    switch (sdk) {
      case SdkType.flutter:
        return 'dart';
      case SdkType.nodejs:
        return 'js';
      case SdkType.reactNative:
        return 'tsx';
      case SdkType.python:
        return 'py';
      case SdkType.androidSdk:
        return 'kt'; // Kotlin is the primary Android language
      case SdkType.swift:
        return 'swift';
      case SdkType.go:
        return 'go';
    }
  }

  // ── Dependency-section extractors (VS Code-style change detection) ──────────
  //
  // Each extractor returns only the dependency-declaring portion of a file.
  // The snapshot taken at load time is compared on every save — the banner
  // appears only when the deps actually changed, not on every save.

  static String _depSection(String content, SdkType sdk) {
    switch (sdk) {
      case SdkType.flutter:
        return _yamlDepSection(content);
      case SdkType.reactNative:
      case SdkType.nodejs:
        return _jsonDepSection(content);
      case SdkType.androidSdk:
        return _gradleDepSection(content);
      case SdkType.go:
        return _goModSection(content);
      default:
        return content; // requirements.txt, etc. — compare whole file
    }
  }

  /// Extracts [dependencies:], [dev_dependencies:], [dependency_overrides:]
  /// blocks from a pubspec.yaml.
  static String _yamlDepSection(String content) {
    const depKeys = {
      'dependencies:',
      'dev_dependencies:',
      'dependency_overrides:',
    };
    final result = StringBuffer();
    bool inSection = false;
    for (final line in content.split('\n')) {
      // A top-level key has no leading whitespace and contains ':'
      final isTopLevel = line.isNotEmpty &&
          !line.startsWith(' ') &&
          !line.startsWith('\t');
      if (isTopLevel) {
        inSection = depKeys.any((k) => line.startsWith(k));
      }
      if (inSection) result.writeln(line);
    }
    return result.toString();
  }

  /// Extracts [dependencies], [devDependencies], [peerDependencies] from
  /// a package.json file.
  static String _jsonDepSection(String content) {
    try {
      final map = jsonDecode(content) as Map<String, dynamic>;
      return jsonEncode({
        'dependencies': map['dependencies'],
        'devDependencies': map['devDependencies'],
        'peerDependencies': map['peerDependencies'],
      });
    } catch (_) {
      return content;
    }
  }

  /// Extracts all [dependencies { }] blocks from a Gradle build script.
  static String _gradleDepSection(String content) {
    final result = StringBuffer();
    int depth = 0;
    bool inDep = false;
    for (int i = 0; i < content.length; i++) {
      if (!inDep) {
        // Look for "dependencies" keyword followed (soon) by '{'
        if (content.startsWith('dependencies', i)) {
          final sub = content.indexOf('{', i + 'dependencies'.length);
          if (sub != -1 && sub - i < 60) {
            inDep = true;
            depth = 1;
            i = sub;
            result.write('dependencies{');
            continue;
          }
        }
      } else {
        final ch = content[i];
        if (ch == '{') {
          depth++;
        } else if (ch == '}') {
          depth--;
          if (depth == 0) {
            result.write('}');
            inDep = false;
            continue;
          }
        }
        result.write(ch);
      }
    }
    return result.toString();
  }

  /// Extracts [require ( ... )] blocks from a go.mod file.
  static String _goModSection(String content) {
    final result = StringBuffer();
    bool inRequire = false;
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('require')) inRequire = true;
      if (inRequire) {
        result.writeln(line);
        if (trimmed == ')') inRequire = false;
      }
    }
    return result.toString();
  }

  void _runSync() {
    // Refresh snapshot so the banner doesn't reappear immediately after syncing.
    if (_syncTriggerPath.isNotEmpty) {
      final file = File(_syncTriggerPath);
      if (file.existsSync()) {
        _depSectionSnapshot = _depSection(
          file.readAsStringSync(),
          widget.project.sdk,
        );
      }
    }
    setState(() {
      _syncBannerVisible = false;
      _initPhase = _InitPhase.syncingDeps;
    });
    // Open OUTPUT tab so the user sees the sync log (VS Code style).
    _sheetKey.currentState?.selectToolTab(5); // 5 = OUTPUT
    _sheetKey.currentState?.expandToMid();
    // Run the sync command as a background process — output streams to OUTPUT tab.
    context.read<BuildProvider>().sync(_syncCommand, widget.project.path).then((_) {
      if (mounted && _initPhase == _InitPhase.syncingDeps) {
        setState(() => _initPhase = _InitPhase.ready);
      }
    });
  }

  void _closeDrawer()    => _drawerCtrl.reverse();
  void _closeAiDrawer()  => _aiDrawerCtrl.reverse();
  void _toggleDrawer() {
    FocusScope.of(context).unfocus();
    if (_drawerCtrl.isCompleted) _drawerCtrl.reverse();
    else _drawerCtrl.forward();
  }
  void _toggleAiDrawer() {
    FocusScope.of(context).unfocus();
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
                snapCoordinator: _snapCoordinator,
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
                                      sheetKey: _sheetKey,
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
                                  sheetKey: _sheetKey,
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
                              onApkTap: _showApkInstallDialog,
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
  final GlobalKey<_BottomSheetPanelState> sheetKey;

  const _WorkspaceAppBar({
    required this.project,
    required this.drawerAnim,
    required this.onMenuTap,
    required this.onAiTap,
    required this.onShowWebPreview,
    required this.liquidGlass,
    required this.sheetKey,
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
    if (platforms.isEmpty) return;

    // Use the last-saved platform directly — no dialog. The user changes the
    // platform via the debug button in the drawer rail (platform-picker sheet).
    final savedName = settings.debugPlatformFor(widget.project.sdk.name);
    final platform = savedName != null
        ? platforms.firstWhere((p) => p.name == savedName,
            orElse: () => platforms.first)
        : platforms.first;

    // Open the bottom sheet on the DEBUG CONSOLE tab (index 4 in the tool tabs)
    // so the user sees build output immediately without having to navigate there.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      widget.sheetKey.currentState?.selectToolTab(4); // 4 = DEBUG CONSOLE
      widget.sheetKey.currentState?.expandToMid();
    });

    // Prefer DapConfig from installed JSON extension, fall back to SdkDefinition.
    final ext = context.read<ExtensionsProvider>().availableSdks
        .where((e) => e.sdk == widget.project.sdk.name)
        .firstOrNull;
    final dapConfig = ext?.dapConfig ??
        SdkDefinition.forType(widget.project.sdk).dapConfig;

    // React Native has no DAP adapter — launch Metro bundler as a run session.
    if (!dapConfig.hasDap && widget.project.sdk == SdkType.reactNative) {
      context.read<DebugProvider>().startMetroSession(widget.project);
      return;
    }

    // Android native has no DAP adapter — run Gradle build instead.
    if (!dapConfig.hasDap && widget.project.sdk == SdkType.androidSdk) {
      final buildCmd = SdkDefinition.forType(SdkType.androidSdk).buildCommand;
      context.read<DebugProvider>().startBuildSession(widget.project, buildCmd);
      return;
    }

    final ssh = context.read<SshProvider>();
    final isRemoteProject = ssh.isConnected &&
        ssh.config != null &&
        ssh.config!.remoteProjectsPath.isNotEmpty &&
        widget.project.path.startsWith(ssh.config!.remoteProjectsPath);

    if (isRemoteProject) {
      final bin = dapConfig.adapterBinary.isNotEmpty ? dapConfig.adapterBinary : 'dart';
      final args = dapConfig.adapterArgs.isNotEmpty ? dapConfig.adapterArgs : ['debug_adapter'];
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
                          year2023: true,
                          color: cs.primary,
                          backgroundColor: Colors.transparent,
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(10),
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
           /*    Text(
                'FL IDE',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ), */
              Text(
                widget.project.name,
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 15,
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
        // ── Web preview button (web DAP or Metro/React-Native session) ───
        Consumer<DebugProvider>(
          builder: (context, dbg, _) {
            if (!dbg.isActive) return const SizedBox.shrink();
            // Always show for Metro (React Native / Expo) sessions.
            if (dbg.isMetroSession) {
              return IconButton(
                icon: Icon(Icons.web_rounded, color: cs.primary, size: 22),
                onPressed: () => _showWebPreview(context),
                tooltip: 'Web Preview',
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              );
            }
            // For DAP sessions show only when the selected platform is web.
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
              case 'repair_android':
                _repairAndroidProject(context);
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
              if (context.read<EditorProvider>().activeFile?.extension == 'dart')
                PopupMenuItem(
                  value: 'visual_editor',
                  height: 40,
                  child: _PopupItem(
                      icon: Icons.auto_awesome_outlined,
                      label: 'Visual Editor'),
                ),
              if (widget.project.sdk == SdkType.flutter ||
                  widget.project.sdk == SdkType.androidSdk)
                PopupMenuItem(
                  value: 'repair_android',
                  height: 40,
                  child: _PopupItem(
                      icon: Icons.build_circle_outlined,
                      label: 'Reparar Android (Termux)'),
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

/// Patches an existing Flutter or native-Android project's gradle.properties:
///  • Lowers Gradle JVM heap to -Xmx512m (prevents OOM-killer on Termux)
///  • Injects android.aapt2FromMavenOverride pointing to the local ARM64 aapt2
void _repairAndroidProject(BuildContext context) {
  final project = context.read<ProjectManagerProvider>().activeProject;
  if (project == null) return;

  final script = project.sdk == SdkType.flutter
      ? ProjectTemplate.repairFlutterAndroid(project.path)
      : ProjectTemplate.repairNativeAndroid(project.path);

  final termProv = context.read<TerminalProvider>();
  final sessions = termProv.sessions;
  if (sessions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Abra o terminal primeiro antes de reparar.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }
  sessions.first.writeCommand(script);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('Executando reparação Android no terminal…'),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// Shows a bottom sheet to change the build platform without starting a build.
void _showPlatformPickerSheet(BuildContext context, Project project) {
  final settings = context.read<SettingsProvider>();
  final platforms = supportedPlatforms(project.sdk);
  if (platforms.isEmpty) return;

  final savedName = settings.debugPlatformFor(project.sdk.name);

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final cs = Theme.of(sheetCtx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 12),
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.developer_board_rounded, color: cs.primary, size: 20),
                      const SizedBox(width: 10),
                      Text(
                        'Plataforma de compilação',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                StatefulBuilder(
                  builder: (_, setState2) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: platforms.map((p) {
                        final isActive = settings.debugPlatformFor(project.sdk.name) == p.name ||
                            (savedName == null && p == platforms.first);
                        final iconData = switch (p) {
                          BuildPlatform.android || BuildPlatform.apk => Icons.android_rounded,
                          BuildPlatform.web => Icons.language_rounded,
                          BuildPlatform.linux => Icons.computer_rounded,
                          _ => Icons.play_circle_outline_rounded,
                        };
                        return InkWell(
                          onTap: () {
                            settings.setDebugPlatform(project.sdk.name, p.name);
                            Navigator.pop(sheetCtx);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Icon(iconData,
                                    color: isActive ? cs.primary : cs.onSurfaceVariant,
                                    size: 22),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    p.label,
                                    style: TextStyle(
                                      color: isActive ? cs.primary : cs.onSurface,
                                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                if (isActive)
                                  Icon(Icons.check_circle_rounded, size: 18, color: cs.primary),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      );
    },
  );
}

Future<void> _confirmCloseProject(BuildContext context) async {
  final cs = Theme.of(context).colorScheme;
  final ss = AppStrings.of(context);
  final confirmed = await showThemedDialog<bool>(
    context: context,
    title: ss.wsCloseProjectQ,
    builder: (ctx) {
      
      return  Padding(
        padding: const EdgeInsets.all(10.0),
        child: Text(ss.wsCloseProjectBody),
      );
       
    },
     actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(ss.no, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: cs.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(ss.wsCloseYes),
          ),
        ],
     
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
  final SnapCoordinator snapCoordinator;

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
    required this.snapCoordinator,
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
        final editorBottomPad = _BottomSheetPanelState._kPeekBarH;

        final stack = Stack(
          children: [
            // ── Editor (full height, dynamic bottom padding) ──────────────
            Padding(
              padding: EdgeInsets.only(bottom: editorBottomPad),
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
                  onDiagnosticTap: () {
                    widget.sheetKey.currentState?.selectToolTab(1); // 1 = PROBLEMS
                    widget.sheetKey.currentState?.expandToMid();
                  },
                ),
              ),
            ),
            // ── Floating debug execution bar ─────────────────────────────
            _DebugExecutionOverlay(coordinator: widget.snapCoordinator),
            // ── Sync banner: anchored at editor bottom, slides in above
            //    the peek bar. Rendered BEFORE the sheet so it stays in
            //    the code area and the sheet slides over it when expanded.
            Positioned(
              left: 0,
              right: 0,
              bottom: _BottomSheetPanelState._kPeekBarH,
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
  final void Function(String apkPath)? onApkTap;

  const _DrawerContent({
    required this.project,
    required this.onClose,
    required this.onTabChange,
    this.onApkTap,
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
                    child: FileTreePanel(
                      onFileSelected: onClose,
                      onApkTap: onApkTap,
                    ),
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
              tooltip: 'Plataforma de build',
              bg: cs.primaryContainer,
              fg: cs.onPrimaryContainer,
              onTap: () => _showPlatformPickerSheet(context, project),
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
  static const int _kToolCount = 7; // TERMINAL PROBLEMS VARIABLES CALL-STACK DEBUG-CONSOLE OUTPUT LOGCAT

  double _height = _kPeek;
  late AnimationController _animCtrl;
  late Animation<double> _anim;

  // Combined tab controller: [file tabs...] + [TERMINAL, PROBLEMS, VARIABLES, CALL STACK, DEBUG CONSOLE, OUTPUT, LOGCAT]
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
  /// Never collapses the sheet when it is already at or above mid — so
  /// repeated calls from the debug console listener don't push the sheet
  /// down when the user has manually pulled it to full height.
  void expandToMid() {
    if (_height < _kMid) _snapTo(_kMid);
  }

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
                                    lsp.status == LspStatus.warming /* ||
                                    dbg.status == DebugStatus.starting ||
                                    dbg.isBuilding */;
                                return loading
                                    ? LinearProgressIndicator(
                                      year2023: true,
                                        minHeight: 2,
                                        backgroundColor: cs.outlineVariant,
                                        borderRadius: BorderRadius.circular(10),
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
                                  const Tab(text: 'DEBUG CONSOLE', height: 40),
                                  const Tab(text: 'OUTPUT', height: 40),
                                  const Tab(text: 'LOGCAT', height: 40),
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
                                  onDiagnosticTap: () {
                                    // _BottomSheetPanelState can call its own
                                    // methods directly — no key lookup needed.
                                    selectToolTab(1); // 1 = PROBLEMS
                                    expandToMid();
                                  },
                                ),
                              )
                            : IndexedStack(
                                index: (tabIdx - bf.length).clamp(0, _kToolCount - 1),
                                children: [
                                  TerminalTabs(
                                    initialWorkDir: widget.project.path,
                                    autoStart: false,
                                  ),
                                  _ProblemsPanel(
                                    onNavigated: () => _snapTo(_kPeek),
                                  ),
                                  const DebugVariablesPanel(),
                                  const DebugCallStackPanel(),
                                  // DEBUG CONSOLE — DAP build/run output
                                  DebugOutputPanel(
                                    onNavigate: (path, line) async {
                                      final editor = context.read<EditorProvider>();
                                      await editor.openFile(path);
                                      final f = editor.openFiles
                                          .where((f) => f.path == path)
                                          .firstOrNull;
                                      f?.controller?.cursor.moveTo(
                                        CharPosition(line - 1, 0),
                                      );
                                    },
                                  ),
                                  // OUTPUT — general logs (git, sync, LSP, etc.)
                                  const _OutputPanel(),
                                  // LOGCAT — live app logs via adb logcat
                                  _LogcatPanel(project: widget.project),
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
        label = s.peekCreatingProject; showProgress = true;
      case _InitPhase.loadingProject:
        label = s.peekLoadingProject;  showProgress = true;
      case _InitPhase.startingLsp:
        label = s.peekStartingLsp;     showProgress = true;
      case _InitPhase.syncingDeps:
        label = s.peekSyncingDeps;     showProgress = true;
      case _InitPhase.ready:
        label = s.peekReady;           showProgress = false;
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
          const SizedBox(height: 4),
          Text(
            showProgress ? '' : s.peekSwipeUp,
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
    // Fully opaque container — no glass, no transparency — sits in editor area.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        border: Border(top: BorderSide(color: cs.primary, width: 2)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.25),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.download_rounded, size: 18, color: cs.onPrimaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  s.syncBannerMsg(command),
                  style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
                ),
              ),
              TextButton(
                onPressed: onIgnore,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onPrimaryContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
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

// ── Diagnostic data model ─────────────────────────────────────────────────────

class _DiagItem {
  final String filePath;
  final String fileName;
  final LspDiagnostic diag;

  int    get line     => diag.range.start.line;
  int    get col      => diag.range.start.column;
  DiagnosticSeverity get severity => diag.severity;
  String get message  => diag.message;

  _DiagItem({required this.filePath, required this.fileName, required this.diag});
}

// ── Problems Panel ────────────────────────────────────────────────────────────
//
// Uses LspProvider.projectDiagnostics so every file the server analyses is
// shown — not just currently open files.

class _ProblemsPanel extends StatelessWidget {
  /// Called after a diagnostic is tapped and the file is opened — use this to
  /// collapse the bottom sheet so the editor becomes visible.
  final VoidCallback? onNavigated;

  const _ProblemsPanel({this.onNavigated});

  /// Converts a file URI (file:///...) to a display name (last path segment).
  static String _nameFromUri(String uri) {
    final decoded = Uri.tryParse(uri)?.toFilePath() ?? uri;
    return decoded.split('/').last;
  }

  /// Converts a file URI to a local file path.
  static String _pathFromUri(String uri) =>
      Uri.tryParse(uri)?.toFilePath() ?? uri;

  @override
  Widget build(BuildContext context) {
    return Consumer2<LspProvider, EditorProvider>(
      builder: (context, lsp, editor, _) {
        final cs = Theme.of(context).colorScheme;

        // ── Collect all items ───────────────────────────────────────────────
        //
        // Primary source: project-wide diagnostics pushed by the LSP server
        // (keyed by file URI). This covers every file the server has analysed.
        //
        // Secondary source: EditorProvider.diagnosticsCache — keeps diagnostics
        // for files the user has opened and whose controllers received a push,
        // persisted even after the tab is closed. Fills gaps when the LSP hasn't
        // notified about a particular URI yet.
        //
        // If neither source has data yet we fall back to whatever the currently
        // open controllers report directly (warm-up phase).

        final allItems = <String, _DiagItem>{};

        void addFromLspDiag(String filePath, String fileName, LspDiagnostic d) {
          final key = '$filePath:${d.range.start.line}:${d.range.start.column}:${d.severity.index}:${d.message}';
          allItems[key] = _DiagItem(filePath: filePath, fileName: fileName, diag: d);
        }

        // 1. LSP project-wide map (URI-keyed).
        for (final entry in lsp.projectDiagnostics.entries) {
          final fp = _pathFromUri(entry.key);
          final fn = _nameFromUri(entry.key);
          for (final d in entry.value) addFromLspDiag(fp, fn, d);
        }

        // 2. EditorProvider persistent cache (filePath-keyed DiagnosticRegions).
        for (final entry in editor.diagnosticsCache.entries) {
          final fp = entry.key;
          final fn = fp.split('/').last.split('\\').last;
          for (final region in entry.value) {
            addFromLspDiag(fp, fn, LspDiagnostic(
              range:    region.range,
              message:  region.message,
              severity: region.severity,
              source:   region.source,
              code:     region.code,
            ));
          }
        }

        // 3. Fallback: live open-file controllers (warm-up phase).
        if (allItems.isEmpty) {
          for (final f in editor.openFiles) {
            final ctrl = f.controller;
            if (ctrl == null) continue;
            for (final region in ctrl.diagnostics.all) {
              addFromLspDiag(f.path, f.name, LspDiagnostic(
                range:    region.range,
                message:  region.message,
                severity: region.severity,
                source:   region.source,
                code:     region.code,
              ));
            }
          }
        }

        final items = allItems.values.toList();

        if (items.isEmpty) {
          final isRunning = lsp.status == LspStatus.warming ||
              lsp.status == LspStatus.ready;
          return _PanelPlaceholder(
            icon: isRunning
                ? Icons.check_circle_outline
                : Icons.folder_open_outlined,
            iconColor: isRunning ? cs.primary : null,
            text: isRunning
                ? 'Sem problemas'
                : 'Abra um arquivo para ver os problemas',
          );
        }

        // ── Split into three groups ─────────────────────────────────────────
        final errors   = items.where((i) => i.severity == DiagnosticSeverity.error).toList();
        final warnings = items.where((i) => i.severity == DiagnosticSeverity.warning).toList();
        final infos    = items.where((i) =>
            i.severity != DiagnosticSeverity.error &&
            i.severity != DiagnosticSeverity.warning).toList();

        // Sort each group by file name then line number.
        int byLocation(_DiagItem a, _DiagItem b) {
          final c = a.fileName.compareTo(b.fileName);
          return c != 0 ? c : a.line.compareTo(b.line);
        }
        errors.sort(byLocation);
        warnings.sort(byLocation);
        infos.sort(byLocation);

        // Build a flat list of section headers + items for ListView.
        final List<_ProblemListEntry> rows = [];
        if (errors.isNotEmpty) {
          rows.add(_ProblemListEntry.header(
            label: 'Erros',
            count: errors.length,
            color: cs.error,
            icon: Icons.highlight_off,
          ));
          rows.addAll(errors.map(_ProblemListEntry.item));
        }
        if (warnings.isNotEmpty) {
          rows.add(_ProblemListEntry.header(
            label: 'Avisos',
            count: warnings.length,
            color: cs.tertiary,
            icon: Icons.warning_amber_rounded,
          ));
          rows.addAll(warnings.map(_ProblemListEntry.item));
        }
        if (infos.isNotEmpty) {
          rows.add(_ProblemListEntry.header(
            label: 'Informações',
            count: infos.length,
            color: cs.primary,
            icon: Icons.info_outline,
          ));
          rows.addAll(infos.map(_ProblemListEntry.item));
        }

        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 8),
          itemCount: rows.length,
          itemBuilder: (context, i) {
            final row = rows[i];
            if (row.isHeader) {
              return _ProblemSectionHeader(
                label:     row.headerLabel!,
                count:     row.headerCount!,
                color:     row.headerColor!,
                icon:      row.headerIcon!,
              );
            }
            final item = row.item!;
            final isError   = item.severity == DiagnosticSeverity.error;
            final isWarning = item.severity == DiagnosticSeverity.warning;
            final iconColor = isError   ? cs.error
                            : isWarning ? cs.tertiary
                                        : cs.primary;
            final icon = isError   ? Icons.highlight_off
                       : isWarning ? Icons.warning_amber_rounded
                                   : Icons.info_outline;

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () => _navigateTo(context, item, editor, onNavigated),
                  child: Padding(
                    padding: const EdgeInsets.only(
                        left: 16, right: 4, top: 8, bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1),
                          child: Icon(icon, size: 14, color: iconColor),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.message,
                                style: TextStyle(
                                    color: cs.onSurface, fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${item.fileName}  ·  Ln ${item.line + 1}, Col ${item.col + 1}',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.content_copy_rounded,
                              size: 14, color: cs.onSurfaceVariant),
                          tooltip: 'Copiar mensagem',
                          padding: const EdgeInsets.all(8),
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Clipboard.setData(ClipboardData(
                            text:
                                '${item.fileName}:${item.line + 1}:${item.col + 1}: ${item.message}',
                          )),
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(color: cs.outlineVariant, height: 1, indent: 16),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _navigateTo(BuildContext context, _DiagItem item,
      EditorProvider editor, VoidCallback? onNavigated) async {
    // Open the file if not already open (reads from disk).  If already open,
    // openFile() now also updates _lastTopIdx so EditorArea switches tabs.
    await editor.openFile(item.filePath);

    // If the file landed in (or was already in) the bottom panel, move it to
    // the top (main) panel so it is visible above the sheet.
    final idx = editor.openFiles.indexWhere((f) => f.path == item.filePath);
    if (idx >= 0 && editor.openFiles[idx].inBottomPanel) {
      editor.moveToPanel(idx, bottom: false);
    }

    // Collapse the bottom sheet first so the editor is fully visible.
    onNavigated?.call();

    // Move the cursor.  We need one post-frame callback so the editor widget
    // has rebuilt with the new active file before we set the cursor — calling
    // moveTo before the rebuild is a no-op because the old controller is still
    // focused.  A second callback scrolls the viewport to the cursor line so
    // the target location is always visible regardless of file length.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final f = editor.openFiles
          .where((f) => f.path == item.filePath)
          .firstOrNull;
      final ctrl = f?.controller;
      if (ctrl == null) return;
      ctrl.cursor.moveTo(CharPosition(item.line, item.col));
      // Schedule a second frame so the scroll viewport catches up.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ctrl.cursor.moveTo(CharPosition(item.line, item.col));
      });
    });
  }
}

// ── Problems panel helpers ────────────────────────────────────────────────────

/// A slot in the flat ListView — either a section header or a diagnostic item.
class _ProblemListEntry {
  final bool isHeader;
  final _DiagItem? item;
  // Header fields
  final String? headerLabel;
  final int?    headerCount;
  final Color?  headerColor;
  final IconData? headerIcon;

  const _ProblemListEntry.item(_DiagItem i)
      : isHeader    = false,
        item        = i,
        headerLabel = null,
        headerCount = null,
        headerColor = null,
        headerIcon  = null;

  const _ProblemListEntry.header({
    required String  label,
    required int     count,
    required Color   color,
    required IconData icon,
  })  : isHeader    = true,
        item        = null,
        headerLabel = label,
        headerCount = count,
        headerColor = color,
        headerIcon  = icon;
}

/// Sticky-style section header used in the Problems panel.
class _ProblemSectionHeader extends StatelessWidget {
  final String   label;
  final int      count;
  final Color    color;
  final IconData icon;

  const _ProblemSectionHeader({
    super.key,
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Output panel — general logs (git, sync, LSP, etc.) ───────────────────────
//
// BuildProvider exposes a string log that captures flutter pub get, git, etc.
// output. We display it in a scrollable monospace text view.

// ── Output panel — general logs (sync, git, gradle via BuildProvider) ─────────
class _OutputPanel extends StatelessWidget {
  const _OutputPanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<BuildProvider>(
      builder: (context, build, _) {
        final log = build.result.output;
        if (log.isEmpty) {
          return const _PanelPlaceholder(
            icon: Icons.output_rounded,
            text: 'Nenhum log ainda.\nSincronize dependências ou use o terminal.',
          );
        }
        return Scrollbar(
          child: SingleChildScrollView(
            reverse: true,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              log,
              style: TextStyle(
                color: cs.onSurface,
                fontSize: 11.5,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Logcat panel ──────────────────────────────────────────────────────────────
//
// Mirrors AndroidIDE's AppLogFragment: color-coded log lines by priority level,
// auto-scroll to bottom, toolbar with level filter + clear + start/stop.

class _LogcatPanel extends StatefulWidget {
  final Project project;
  const _LogcatPanel({required this.project});

  @override
  State<_LogcatPanel> createState() => _LogcatPanelState();
}

class _LogcatPanelState extends State<_LogcatPanel> {
  final _scrollCtrl = ScrollController();
  bool _autoScroll  = true;
  LogLevel? _filter; // null = ALL levels

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final atBottom = _scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 40;
    if (atBottom != _autoScroll) {
      setState(() => _autoScroll = atBottom);
    }
  }

  void _scrollToBottom() {
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;

    return Consumer<LogcatProvider>(
      builder: (context, logcat, _) {
        // Auto-scroll when new lines arrive (if not manually scrolled up)
        if (_autoScroll && logcat.lines.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scrollCtrl.hasClients &&
                _scrollCtrl.position.maxScrollExtent > 0) {
              _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
            }
          });
        }

        final lines = _filter == null
            ? logcat.lines
            : logcat.lines.where((l) => l.level == _filter).toList();

        return Column(
          children: [
            // ── Toolbar ──────────────────────────────────────────────────────
            Container(
              height: 36,
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  // Status indicator — green = running, teal = bridge connected
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: logcat.bridgeConnected
                          ? Colors.tealAccent.shade400
                          : logcat.isRunning
                              ? Colors.green
                              : cs.outlineVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      logcat.bridgeConnected
                          ? '${logcat.packageName ?? ''} [bridge]'
                          : logcat.packageName ?? 'No app selected',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.7),
                        fontFamily: 'monospace',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Bridge inject / remove button
                  _BridgeButton(project: widget.project),
                  // Level filter chips
                  _LevelChip(label: 'ALL', selected: _filter == null,
                      onTap: () => setState(() => _filter = null)),
                  _LevelChip(label: 'E', color: const Color(0xFFEF5350),
                      selected: _filter == LogLevel.error,
                      onTap: () => setState(() => _filter = LogLevel.error)),
                  _LevelChip(label: 'W', color: const Color(0xFFFFA726),
                      selected: _filter == LogLevel.warning,
                      onTap: () => setState(() => _filter = LogLevel.warning)),
                  _LevelChip(label: 'I', color: const Color(0xFF66BB6A),
                      selected: _filter == LogLevel.info,
                      onTap: () => setState(() => _filter = LogLevel.info)),
                  _LevelChip(label: 'D', selected: _filter == LogLevel.debug,
                      onTap: () => setState(() => _filter = LogLevel.debug)),
                  _LevelChip(label: 'V', color: const Color(0xFF4FC3F7),
                      selected: _filter == LogLevel.verbose,
                      onTap: () => setState(() => _filter = LogLevel.verbose)),
                  const SizedBox(width: 4),
                  // Clear
                  IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
                    tooltip: 'Clear',
                    onPressed: () => logcat.clear(),
                  ),
                  // Start / Stop
                  if (logcat.isRunning)
                    IconButton(
                      icon: Icon(Icons.stop_circle_outlined, size: 16,
                          color: cs.error),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
                      tooltip: 'Stop logcat',
                      onPressed: () => logcat.stop(),
                    )
                  else
                    IconButton(
                      icon: Icon(Icons.play_circle_outlined, size: 16,
                          color: cs.primary),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
                      tooltip: 'Start logcat',
                      onPressed: () {
                        final pkg = logcat.packageName
                            ?? LogcatProvider.detectPackageName(widget.project.path);
                        if (pkg != null) logcat.start(pkg);
                      },
                    ),
                  // Scroll-to-bottom (visible only when auto-scroll is off)
                  if (!_autoScroll)
                    IconButton(
                      icon: const Icon(Icons.arrow_downward, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
                      tooltip: 'Scroll to bottom',
                      onPressed: () {
                        setState(() => _autoScroll = true);
                        _scrollToBottom();
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            // ── Log lines ────────────────────────────────────────────────────
            Expanded(
              child: lines.isEmpty
                  ? _LogcatPlaceholder(
                      project: widget.project,
                      isRunning: logcat.isRunning,
                    )
                  : SelectionArea(
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        itemCount: lines.length,
                        itemExtent: null,
                        padding: const EdgeInsets.only(bottom: 8),
                        itemBuilder: (_, i) {
                          final line = lines[i];
                          final color   = line.textColor(brightness);
                          final bgColor = line.rowBackground(brightness);

                          // System separator
                          if (line.level == LogLevel.system) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 2),
                              child: Text(
                                line.message,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontFamily: 'monospace',
                                  color: cs.onSurface.withValues(alpha: 0.4),
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            );
                          }

                          return Container(
                            color: bgColor,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 1),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  height: 1.45,
                                  color: color,
                                ),
                                children: [
                                  // time (HH:MM:SS.mmm)
                                  TextSpan(
                                    text: '${line.time.length > 12 ? line.time.substring(0, 12) : line.time}  ',
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  // level char — bold
                                  TextSpan(
                                    text: '${line.levelChar}  ',
                                    style: TextStyle(
                                      color: color,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  // tag
                                  TextSpan(
                                    text: '${line.tag}: ',
                                    style: TextStyle(
                                      color: cs.onSurface.withValues(alpha: 0.65),
                                    ),
                                  ),
                                  // message
                                  TextSpan(text: line.message),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

// ── Logcat placeholder ────────────────────────────────────────────────────────
// Shows "waiting" when running, or an actionable "Install APK" button when
// there's a pre-built APK available (e.g. from `flutter build apk`).

class _LogcatPlaceholder extends StatelessWidget {
  final Project project;
  final bool isRunning;
  const _LogcatPlaceholder({required this.project, required this.isRunning});

  @override
  Widget build(BuildContext context) {
    if (isRunning) {
      return const _PanelPlaceholder(
        icon: Icons.pest_control_outlined,
        text: 'Waiting for app to start…',
      );
    }

    final logcat = context.read<LogcatProvider>();

    // Show setup error card (READ_LOGS not granted, etc.)
    if (logcat.setupError != null) {
      return _LogcatSetupCard(error: logcat.setupError!);
    }

    // Check if there's an APK available from a terminal build.
    final apkPath = LogcatProvider.findLatestApk(project.path);

    if (apkPath == null) {
      return const _PanelPlaceholder(
        icon: Icons.pest_control_outlined,
        text: 'No logs yet.\nBuild and install the app to start logcat.',
      );
    }

    final cs = Theme.of(context).colorScheme;
    final apkName = apkPath.split('/').last;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.android_rounded, size: 28, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            apkName,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.7),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonal(
            onPressed: () {
              final ws = context.findAncestorStateOfType<_WorkspaceScreenState>();
              ws?._showApkInstallDialog(apkPath);
            },
            child: const Text('Install & Watch Logcat'),
          ),
          const SizedBox(height: 4),
          Text(
            'APK found from terminal build',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogcatSetupCard extends StatelessWidget {
  final String error;
  const _LogcatSetupCard({required this.error});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Extract the command line from the error string for the copy button.
    final cmdMatch = RegExp(r'(adb shell pm grant [^\n]+)').firstMatch(error);
    final cmd = cmdMatch?.group(1) ?? '';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.terminal_rounded, size: 28,
                color: cs.error.withValues(alpha: 0.8)),
            const SizedBox(height: 10),
            Text(
              'Logcat permission required',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant READ_LOGS to Termux once from a PC or '
              'Wireless ADB — then tap play again.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
            if (cmd.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        cmd,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.copy_rounded, size: 14),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                          maxWidth: 24, maxHeight: 24),
                      tooltip: 'Copy command',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: cmd));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Command copied'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Bridge inject/remove button ───────────────────────────────────────────────

class _BridgeButton extends StatefulWidget {
  final Project project;
  const _BridgeButton({required this.project});

  @override
  State<_BridgeButton> createState() => _BridgeButtonState();
}

class _BridgeButtonState extends State<_BridgeButton> {
  late bool _injected;

  @override
  void initState() {
    super.initState();
    _injected = LogBridgeInjector.isInjected(widget.project);
  }

  void _toggle() {
    final cs = Theme.of(context).colorScheme;

    if (_injected) {
      // Remove bridge files
      showThemedDialog(
        context: context,
        title: 'Remove Log Bridge?',
        builder: (_) => const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'This will delete the FL IDE Log Bridge files from your project.\n'
            'You will need to rebuild the app afterwards.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              LogBridgeInjector.remove(widget.project);
              setState(() => _injected = false);
            },
            child: const Text('Remove'),
          ),
        ],
      );
    } else {
      // Inject bridge files
      final err = LogBridgeInjector.inject(widget.project);
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bridge injection failed: $err')),
        );
        return;
      }
      setState(() => _injected = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Log Bridge injected. Rebuild the app to activate.',
          ),
          backgroundColor: cs.primaryContainer,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      icon: Icon(
        _injected ? Icons.cable_rounded : Icons.cable_outlined,
        size: 15,
        color: _injected ? Colors.tealAccent.shade400 : cs.onSurface.withValues(alpha: 0.5),
      ),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(maxWidth: 28, maxHeight: 28),
      tooltip: _injected ? 'Remove Log Bridge from project' : 'Inject Log Bridge into project',
      onPressed: _toggle,
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String label;
  final Color? color;
  final bool selected;
  final VoidCallback onTap;

  const _LevelChip({
    required this.label,
    this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? (color ?? cs.primary).withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: selected
              ? Border.all(color: (color ?? cs.primary).withValues(alpha: 0.5))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: selected ? fg : cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }
}

// ── Panel placeholder ─────────────────────────────────────────────────────────

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
// ── Platform picker dialog ────────────────────────────────────────────────────

class _PlatformPickerDialog extends StatefulWidget {
  final List<BuildPlatform> platforms;
  final BuildPlatform initial;

  const _PlatformPickerDialog({
    required this.platforms,
    required this.initial,
  });

  @override
  State<_PlatformPickerDialog> createState() => _PlatformPickerDialogState();
}

class _PlatformPickerDialogState extends State<_PlatformPickerDialog> {
  late BuildPlatform _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  static IconData _iconFor(BuildPlatform p) => switch (p) {
    BuildPlatform.android || BuildPlatform.apk => Icons.android_rounded,
    BuildPlatform.web => Icons.language_rounded,
    BuildPlatform.linux => Icons.computer_rounded,
    _ => Icons.play_circle_outline_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.bug_report_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Selecionar dispositivo'),
        ],
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: widget.platforms.map((p) {
          final selected = p == _selected;
          return InkWell(
            onTap: () => setState(() => _selected = p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    _iconFor(p),
                    color: selected ? cs.primary : cs.onSurfaceVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      p.label,
                      style: TextStyle(
                        color: selected ? cs.primary : cs.onSurface,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle_rounded,
                        size: 18, color: cs.primary),
                ],
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('Executar'),
          onPressed: () => Navigator.pop(context, _selected),
        ),
      ],
    );
  }
}

// Appears at the bottom of the editor (above the bottom sheet) when a DAP
// session is active. Shows status, current stopped location, and quick actions.

class _DebugExecutionOverlay extends StatefulWidget {
  final SnapCoordinator coordinator;
  const _DebugExecutionOverlay({required this.coordinator});

  @override
  State<_DebugExecutionOverlay> createState() => _DebugExecutionOverlayState();
}

class _DebugExecutionOverlayState extends State<_DebugExecutionOverlay> {
  // Start near top-left, below the status bar area
  Offset _pos = const Offset(16, 48);

  /// Edge-snap state.
  bool _snapped  = false;
  bool _snapLeft = true;
  /// Cumulative drag distance away from the snapped edge (resets on reversal).
  double _dragAwayAccum = 0.0;

  static const double _kSnapThreshold  = 60.0;
  static const double _kApproxBarWidth = 230.0;
  static const double _kTabWidth       = 40.0;
  static const double _kDockedTabH     = 96.0; // approx height of _DockedDebugTab
  /// How far the user must drag back into the screen to un-snap.
  static const double _kUnSnapThreshold = 28.0;

  @override
  void initState() {
    super.initState();
    widget.coordinator.addListener(_onCoordChanged);
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onCoordChanged);
    widget.coordinator.clear(SnapCoordinator.slotDap);
    super.dispose();
  }

  void _onCoordChanged() => setState(() {});

  void _onPanUpdate(DragUpdateDetails d, Size screen) {
    if (_snapped) {
      // While snapped allow Y-axis sliding.
      final ny = (_pos.dy + d.delta.dy).clamp(0.0, screen.height - _kDockedTabH);
      setState(() => _pos = Offset(_pos.dx, ny));
      // Notify coordinator of new desired Y.
      widget.coordinator.update(SnapCoordinator.slotDap,
          active: true, left: _snapLeft, y: ny, h: _kDockedTabH);

      // Accumulate drag away from the edge.  Reversing direction resets the
      // counter so only a deliberate continuous drag un-snaps the bar.
      final awayDelta = _snapLeft ? d.delta.dx : -d.delta.dx;
      if (awayDelta > 0) {
        _dragAwayAccum += awayDelta;
      } else {
        _dragAwayAccum = 0;
      }
      if (_dragAwayAccum >= _kUnSnapThreshold) {
        setState(() {
          _snapped = false;
          _dragAwayAccum = 0;
          _pos = Offset(
            _snapLeft ? _kTabWidth + 8 : screen.width - _kApproxBarWidth - 8,
            _pos.dy,
          );
        });
        widget.coordinator.clear(SnapCoordinator.slotDap);
      }
    } else {
      setState(() {
        final nx = (_pos.dx + d.delta.dx).clamp(0.0, screen.width - 10);
        final ny = (_pos.dy + d.delta.dy).clamp(0.0, screen.height - 10);
        _pos = Offset(nx, ny);
      });
    }
  }

  void _onPanEnd(DragEndDetails d, Size screen) {
    if (_snapped) return;
    final velX     = d.velocity.pixelsPerSecond.dx;
    final nearLeft  = _pos.dx < _kSnapThreshold || velX < -500;
    final nearRight = _pos.dx + _kApproxBarWidth > screen.width - _kSnapThreshold || velX > 500;
    if (nearLeft && !nearRight) {
      setState(() { _snapped = true; _snapLeft = true; _dragAwayAccum = 0; });
      widget.coordinator.update(SnapCoordinator.slotDap,
          active: true, left: true, y: _pos.dy, h: _kDockedTabH);
    } else if (nearRight) {
      setState(() { _snapped = true; _snapLeft = false; _dragAwayAccum = 0; });
      widget.coordinator.update(SnapCoordinator.slotDap,
          active: true, left: false, y: _pos.dy, h: _kDockedTabH);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Wrap in a full-area Stack so Positioned works freely.
    // Touches on the transparent background pass through to the workspace.
    return Stack(
      fit: StackFit.expand,
      children: [
        Consumer<DebugProvider>(
          builder: (context, dbg, _) {
            if (!dbg.isActive) {
              // Clear coordinator slot when session ends (e.g. after stop).
              if (_snapped) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) {
                    setState(() { _snapped = false; _dragAwayAccum = 0; });
                    widget.coordinator.clear(SnapCoordinator.slotDap);
                  }
                });
              }
              return const SizedBox.shrink();
            }
            final screen = MediaQuery.of(context).size;

            // ── Snapped to edge: compact vertical tab ────────────────────
            if (_snapped) {
              // Use coordinator to avoid overlap with the WebPreview bubble.
              final displayY = widget.coordinator.resolveY(
                SnapCoordinator.slotDap, _snapLeft,
                _pos.dy, _kDockedTabH, screen.height);
              return Positioned(
                left:  _snapLeft ? 0 : null,
                right: _snapLeft ? null : 0,
                top: displayY,
                child: GestureDetector(
                  onPanUpdate: (d) => _onPanUpdate(d, screen),
                  onPanEnd:    (d) => _onPanEnd(d, screen),
                  child: _DockedDebugTab(dbg: dbg, snapLeft: _snapLeft),
                ),
              );
            }

            // ── Free-floating bar ────────────────────────────────────────
            return _FloatingDebugBar(
              dbg: dbg,
              pos: _pos,
              onPan:    (d) => _onPanUpdate(d, screen),
              onPanEnd: (d) => _onPanEnd(d, screen),
            );
          },
        ),
      ],
    );
  }
}

// ── Floating debug bar pill ───────────────────────────────────────────────────

class _FloatingDebugBar extends StatelessWidget {
  final DebugProvider dbg;
  final Offset pos;
  final ValueChanged<DragUpdateDetails> onPan;
  final ValueChanged<DragEndDetails>    onPanEnd;

  const _FloatingDebugBar({
    required this.dbg,
    required this.pos,
    required this.onPan,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final paused = dbg.isPaused;
    final isMetro = dbg.isMetroSession;

    final statusColor = dbg.status == DebugStatus.starting
        ? Colors.blueGrey
        : paused
            ? Colors.orange
            : Colors.green;

    final String statusText;
    if (dbg.status == DebugStatus.starting) {
      statusText = isMetro ? 'Metro…' : 'Iniciando…';
    } else if (paused && dbg.stoppedFile != null) {
      statusText = '${dbg.stoppedFile!.split('/').last}:${dbg.stoppedLine}';
    } else if (paused) {
      statusText = dbg.stopReason ?? 'Pausado';
    } else {
      statusText = isMetro ? 'Metro' : 'Rodando';
    }

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: onPan,
        onPanEnd:    onPanEnd,
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          color: cs.surfaceContainerHighest,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: statusColor.withValues(alpha: 0.5),
                width: 1.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Drag handle ──────────────────────────────────────────
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 4),

                // ── Status dot ───────────────────────────────────────────
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),

                // ── Status label ─────────────────────────────────────────
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 88),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // ── Divider ──────────────────────────────────────────────
                Container(
                  width: 1,
                  height: 20,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: cs.outlineVariant.withValues(alpha: 0.5),
                ),

                // ── Context-sensitive buttons ────────────────────────────
                if (!isMetro && paused) ...[
                  _OverlayBtn(
                    icon: Icons.play_arrow_rounded,
                    tooltip: 'Continuar',
                    color: Colors.green,
                    onTap: dbg.continueExec,
                  ),
                  _OverlayBtn(
                    icon: Icons.redo_rounded,
                    tooltip: 'Step Over',
                    onTap: dbg.stepOver,
                  ),
                  _OverlayBtn(
                    icon: Icons.south_rounded,
                    tooltip: 'Step In',
                    onTap: dbg.stepIn,
                  ),
                  _OverlayBtn(
                    icon: Icons.north_rounded,
                    tooltip: 'Step Out',
                    onTap: dbg.stepOut,
                  ),
                ] else if (!isMetro && dbg.isRunning) ...[
                  _OverlayBtn(
                    icon: Icons.pause_rounded,
                    tooltip: 'Pausar',
                    onTap: dbg.pause,
                  ),
                  _OverlayBtn(
                    icon: Icons.electric_bolt_rounded,
                    tooltip: 'Hot Reload',
                    color: Colors.orange,
                    onTap: dbg.hotReload,
                  ),
                  _OverlayBtn(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Restart',
                    onTap: dbg.restart,
                  ),
                ] else if (isMetro && dbg.isRunning) ...[
                  _OverlayBtn(
                    icon: Icons.electric_bolt_rounded,
                    tooltip: 'Recarregar Bundle',
                    color: Colors.orange,
                    onTap: dbg.hotReload,
                  ),
                  _OverlayBtn(
                    icon: Icons.refresh_rounded,
                    tooltip: 'Reiniciar Metro',
                    onTap: dbg.restart,
                  ),
                ],

                // ── Stop — always shown ──────────────────────────────────
                _OverlayBtn(
                  icon: Icons.stop_rounded,
                  tooltip: 'Parar',
                  color: cs.error,
                  onTap: dbg.stopSession,
                ),

                const SizedBox(width: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Docked debug tab (snapped to screen edge) ─────────────────────────────────

class _DockedDebugTab extends StatelessWidget {
  final DebugProvider dbg;
  final bool snapLeft;

  const _DockedDebugTab({required this.dbg, required this.snapLeft});

  @override
  Widget build(BuildContext context) {
    final cs      = Theme.of(context).colorScheme;
    final paused  = dbg.isPaused;
    final running = dbg.isRunning && !paused;
    final isMetro = dbg.isMetroSession;

    final statusColor = paused ? Colors.orange : running ? Colors.green : Colors.blueGrey;
    final radius = const Radius.circular(12);
    final br = snapLeft
        ? BorderRadius.only(topRight: radius, bottomRight: radius)
        : BorderRadius.only(topLeft: radius, bottomLeft: radius);

    return Material(
      elevation: 8,
      borderRadius: br,
      color: cs.surfaceContainerHighest,
      shadowColor: Colors.black.withValues(alpha: 0.3),
      child: Container(
        width: 40,
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          borderRadius: br,
          border: Border.all(
            color: statusColor.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag-handle indicator
            Icon(
              Icons.drag_handle_rounded,
              size: 14,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 4),

            // Primary action: hot reload (running) or continue (paused)
            if (running)
              _OverlayBtn(
                icon: Icons.electric_bolt_rounded,
                tooltip: isMetro ? 'Recarregar Bundle' : 'Hot Reload',
                color: Colors.orange,
                onTap: dbg.hotReload,
              )
            else if (paused)
              _OverlayBtn(
                icon: Icons.play_arrow_rounded,
                tooltip: 'Continuar',
                color: Colors.green,
                onTap: dbg.continueExec,
              ),

            const SizedBox(height: 2),

            // Stop — always shown
            _OverlayBtn(
              icon: Icons.stop_rounded,
              tooltip: 'Parar',
              color: cs.error,
              onTap: dbg.stopSession,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overlay action button ─────────────────────────────────────────────────────

class _OverlayBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color? color;
  final VoidCallback onTap;

  const _OverlayBtn({
    required this.icon,
    required this.tooltip,
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
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 6),
          child: Icon(icon, size: 17, color: c),
        ),
      ),
    );
  }
}

