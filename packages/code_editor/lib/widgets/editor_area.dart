import 'dart:io';

import 'package:core/core.dart';
import 'package:dap_client/dap_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:progress_indicator_m3e/progress_indicator_m3e.dart';
import 'package:provider/provider.dart';
import 'package:quill_code/quill_code.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/editor_provider.dart';
import 'editor_tab_bar.dart';

class EditorArea extends StatelessWidget {
  final EditorTheme? editorTheme;
  /// Called each build to configure editor props. [fileExtension] is the
  /// extension of the currently active file (e.g. 'dart', 'ts'), or null.
  final void Function(EditorProps props)? configureProps;
  final bool showSymbolBar;
  final double? fontSize;
  final String? fontFamily;
  final bool showTabBar;
  final bool forBottomPanel;

  /// Called when the user taps the diagnostic count in the status bar.
  /// Wired by the host screen to open the Problems panel.
  final VoidCallback? onDiagnosticTap;

  /// Called when the editor's vertical scroll direction changes.
  /// `true` = scrolling down, `false` = scrolling up.
  final ValueChanged<bool>? onScrollDirectionChanged;

  /// When provided, the EditorTabBar slides up (hides) as the value goes
  /// from 0.0 → 1.0 (immersive mode) and slides back down on reverse.
  final Animation<double>? immersiveAnim;

  const EditorArea({
    super.key,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
    this.showTabBar = true,
    this.forBottomPanel = false,
    this.onDiagnosticTap,
    this.onScrollDirectionChanged,
    this.immersiveAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        final active = forBottomPanel
            ? editor.bottomActiveFile
            : editor.topActiveFile;

        // Build tab bar widget (may be animated or static)
        Widget? tabBarWidget;
        if (showTabBar) {
          const tabBar = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EditorTabBar(),
              Divider(height: 1, thickness: 1),
            ],
          );

          if (immersiveAnim != null) {
            tabBarWidget = AnimatedBuilder(
              animation: immersiveAnim!,
              builder: (context, child) {
                final t = immersiveAnim!.value;
                return ClipRect(
                  child: Align(
                    alignment: Alignment.topCenter,
                    heightFactor: (1.0 - t).clamp(0.0, 1.0),
                    child: child,
                  ),
                );
              },
              child: tabBar,
            );
          } else {
            tabBarWidget = tabBar;
          }
        }

        return Column(
          children: [
            if (tabBarWidget != null) tabBarWidget,
            Expanded(
              child: forBottomPanel
                  ? _EditorContent(
                      file: active,
                      editorTheme: editorTheme,
                      configureProps: configureProps,
                      showSymbolBar: showSymbolBar,
                      fontSize: fontSize,
                      fontFamily: fontFamily,
                      forBottomPanel: true,
                      onDiagnosticTap: onDiagnosticTap,
                    )
                  : _MainContent(
                      file: active,
                      editorTheme: editorTheme,
                      configureProps: configureProps,
                      showSymbolBar: showSymbolBar,
                      fontSize: fontSize,
                      fontFamily: fontFamily,
                      onDiagnosticTap: onDiagnosticTap,
                      onScrollDirectionChanged: onScrollDirectionChanged,
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Main (top) content: watches only isTopBarTerminalActive + topBarActiveId
/// from TerminalProvider so terminal output never triggers editor rebuilds.
class _MainContent extends StatelessWidget {
  final OpenFile? file;
  final EditorTheme? editorTheme;
  final void Function(EditorProps props)? configureProps;
  final bool showSymbolBar;
  final double? fontSize;
  final String? fontFamily;
  final VoidCallback? onDiagnosticTap;
  final ValueChanged<bool>? onScrollDirectionChanged;

  const _MainContent({
    required this.file,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
    this.onDiagnosticTap,
    this.onScrollDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Selector<TerminalProvider, (bool, String?)>(
      selector: (_, t) => (t.isTopBarTerminalActive, t.topBarActiveId),
      builder: (context, termState, _) {
        final (isTermActive, _) = termState;
        if (isTermActive) {
          final session = context.read<TerminalProvider>().topBarActiveSession;
          if (session != null) {
            return PtyTerminalWidget(session: session);
          }
        }
        return _EditorContent(
          file: file,
          editorTheme: editorTheme,
          configureProps: configureProps,
          showSymbolBar: showSymbolBar,
          fontSize: fontSize,
          fontFamily: fontFamily,
          forBottomPanel: false,
          onDiagnosticTap: onDiagnosticTap,
          onScrollDirectionChanged: onScrollDirectionChanged,
        );
      },
    );
  }
}

class _EditorContent extends StatelessWidget {
  final OpenFile? file;
  final EditorTheme? editorTheme;
  final void Function(EditorProps props)? configureProps;
  final bool showSymbolBar;
  final double? fontSize;
  final String? fontFamily;
  final bool forBottomPanel;
  final VoidCallback? onDiagnosticTap;
  final ValueChanged<bool>? onScrollDirectionChanged;

  const _EditorContent({
    required this.file,
    required this.forBottomPanel,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
    this.onDiagnosticTap,
    this.onScrollDirectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final active = file;
    if (active == null) return const _WelcomePane();
    return _ActiveEditor(
      file: active,
      editorTheme: editorTheme,
      configureProps: configureProps,
      showSymbolBar: showSymbolBar,
      fontSize: fontSize,
      fontFamily: fontFamily,
      forBottomPanel: forBottomPanel,
      onDiagnosticTap: onDiagnosticTap,
      onScrollDirectionChanged: onScrollDirectionChanged,
    );
  }
}

class _ActiveEditor extends StatefulWidget {
  final OpenFile file;
  final EditorTheme? editorTheme;
  final void Function(EditorProps props)? configureProps;
  final bool showSymbolBar;
  final double? fontSize;
  final String? fontFamily;
  final bool forBottomPanel;
  final VoidCallback? onDiagnosticTap;
  final ValueChanged<bool>? onScrollDirectionChanged;

  const _ActiveEditor({
    required this.file,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
    this.forBottomPanel = false,
    this.onDiagnosticTap,
    this.onScrollDirectionChanged,
  });

  @override
  State<_ActiveEditor> createState() => _ActiveEditorState();
}

class _ActiveEditorState extends State<_ActiveEditor> {
  Set<int> _lastKnownBreakpoints = {};
  DebugProvider? _debugProvider;
  LspProvider? _lspProvider;
  QuillLspConfig? _cachedLspConfig;
  bool _applyingLineStyles = false;

  /// The LSP process we started. Owned here so we can reuse it across file
  /// switches (avoiding a new process per file) and shut it down cleanly when
  /// this state disposes. QuillCodeEditor receives it via lspClient (not
  /// lspConfig) so it never spawns its own process.
  LspClient? _ownedLspClient;

  @override
  void initState() {
    super.initState();
    widget.file.controller?.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncBreakpointsIn();
      _applyDebugLine();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final newDbg = Provider.of<DebugProvider>(context, listen: false);
    if (newDbg != _debugProvider) {
      _debugProvider?.removeListener(_applyDebugLine);
      _debugProvider = newDbg;
      _debugProvider!.addListener(_applyDebugLine);
    }
    final newLsp = Provider.of<LspProvider>(context, listen: false);
    if (newLsp != _lspProvider) {
      _lspProvider?.removeListener(_onLspChanged);
      _lspProvider = newLsp;
      _lspProvider!.addListener(_onLspChanged);
      _cachedLspConfig = newLsp.lspConfig;
    }
  }

  void _onLspChanged() {
    final newConfig = _lspProvider?.lspConfig;
    if (newConfig == _cachedLspConfig || !mounted) return;
    _cachedLspConfig = newConfig;
    if (newConfig == null) {
      // LSP stopped — shut down owned process.
      final old = _ownedLspClient;
      _ownedLspClient = null;
      old?.shutdown();
      _lspProvider?.notifyFileClosedOnLsp(Uri.file(widget.file.path).toString());
      widget.file.controller?.detachLsp();
      _lspProvider?.detachClient(); // also clears _activelyOpenUris
      setState(() {});
      return;
    }
    // LSP config arrived — start the process and attach to current file.
    _startLspAndAttach(newConfig, widget.file);
  }

  Future<void> _startLspAndAttach(QuillLspConfig cfg, OpenFile file) async {
    LspClient? client;
    try {
      if (cfg is QuillLspStdioConfig) {
        client = await LspStdioClient.start(
          executable:               cfg.executable,
          args:                     cfg.args,
          workspacePath:            cfg.workspacePath,
          languageId:               cfg.languageId,
          environment:              cfg.environment,
          initializeTimeoutSeconds: cfg.initializeTimeoutSeconds,
          initializationOptions:    cfg.initializationOptions,
          startupDelayMs:           cfg.startupDelayMs,
          // Wire onError so crashes and timeouts surface in the UI.
          // JVM-based servers (jdtls, kotlin-ls, LemMinX) always write
          // harmless lines to stderr during startup (JAVA_TOOL_OPTIONS
          // echo, SLF4J warnings, OSGi class-loader progress).  Calling
          // setError() on every stderr byte would flip the UI into an
          // error state while the server is still initialising normally,
          // so we only forward truly fatal messages.
          onError: (msg) {
            if (!mounted) return;
            final fatal = msg.contains('timed out after') ||
                          msg.contains('exited with code') ||
                          msg.contains('write error');
            if (fatal) context.read<LspProvider>().setError(msg);
          },
        );
      } else if (cfg is QuillLspSocketConfig) {
        final sc = LspSocketClient(
          serverUrl:     cfg.url,
          workspacePath: cfg.workspacePath,
          languageId:    cfg.languageId,
        );
        sc.onError = (msg) {
          if (mounted) context.read<LspProvider>().setError(msg);
        };
        await sc.connect();
        client = sc;
      }
    } catch (e) {
      debugPrint('[EditorArea] LSP start failed: $e');
      if (mounted) {
        context.read<LspProvider>().setError('LSP failed to start: $e');
      }
      return;
    }
    if (!mounted || client == null) { client?.shutdown(); return; }

    // If initialize timed out, _ready is false — surface the error instead of
    // attaching a non-functional client.
    if (!client.isReady) {
      debugPrint('[EditorArea] LSP client not ready after start, discarding');
      client.shutdown();
      if (mounted) {
        final timeoutSecs = cfg is QuillLspStdioConfig
            ? cfg.initializeTimeoutSeconds
            : null;
        context.read<LspProvider>().setError(
          'LSP (${cfg.languageId}) failed to initialize'
          '${timeoutSecs != null ? ' within ${timeoutSecs}s' : ''}. '
          'The server may need more time on first run.',
        );
      }
      return;
    }

    _ownedLspClient = client;
    // Wire project-wide diagnostics listener so the Problems panel shows
    // issues from every file the server analyses, not just the open one.
    if (mounted) context.read<LspProvider>().attachClient(client);
    final langId = cfg.languageId;
    final fileUri = Uri.file(file.path).toString();
    await file.controller?.attachLsp(
      client,
      uri:        fileUri,
      languageId: langId,
    );
    // Register this URI as actively open so LspProvider knows empty diagnostic
    // pushes for it mean "genuinely clean" (not just a didClose side-effect).
    if (mounted) context.read<LspProvider>().notifyFileOpenedOnLsp(fileUri);
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_ActiveEditor old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      old.file.controller?.removeListener(_onControllerChanged);
      widget.file.controller?.addListener(_onControllerChanged);
      _syncBreakpointsIn();
      _applyDebugLine();
      // Re-bind the existing LSP process to the new file without spawning
      // a second process. Send didClose for the old URI, didOpen for the new.
      final client = _ownedLspClient;
      if (client != null && _cachedLspConfig != null) {
        final langId  = _cachedLspConfig!.languageId;
        final oldUri  = Uri.file(old.file.path).toString();
        final newUri  = Uri.file(widget.file.path).toString();
        // Tab switch — do NOT send didClose.  The server keeps the file open
        // and continues pushing diagnostics for it, so the project-wide
        // Problems panel retains all files' issues regardless of which tab
        // is currently active.
        if (mounted) context.read<LspProvider>().notifyFileClosedOnLsp(oldUri);
        old.file.controller?.detachLsp(sendClose: false);
        widget.file.controller?.attachLsp(
          client,
          uri:        newUri,
          languageId: langId,
        );
        if (mounted) context.read<LspProvider>().notifyFileOpenedOnLsp(newUri);
      }
    }
  }

  @override
  void dispose() {
    widget.file.controller?.removeListener(_onControllerChanged);
    _debugProvider?.removeListener(_applyDebugLine);
    _lspProvider?.removeListener(_onLspChanged);
    // Shut down the LSP process when the editor state is destroyed.
    _ownedLspClient?.shutdown();
    _ownedLspClient = null;
    super.dispose();
  }

  void _applyDebugLine() {
    if (!mounted) return;
    final ctrl = widget.file.controller;
    if (ctrl == null) return;
    final dbg = _debugProvider;
    if (dbg == null) return;
    final stoppedHere = dbg.isPaused &&
        dbg.stoppedFile == widget.file.path &&
        dbg.stoppedLine != null;
    _applyingLineStyles = true;
    if (stoppedHere) {
      ctrl.setLineStyles({
        dbg.stoppedLine!: LineStyle(
          lineBackground: Colors.orange.withValues(alpha: 0.25),
          gutterMarkerColor: Colors.orange,
          gutterMarkerWidth: 4,
        ),
      });
    } else {
      ctrl.setLineStyles({});
    }
    _applyingLineStyles = false;
  }

  void _syncBreakpointsIn() {
    final ctrl = widget.file.controller;
    if (ctrl == null) return;
    final dbg = context.read<DebugProvider>();
    final lines = dbg.breakpointsForFile(widget.file.path).toSet();
    _lastKnownBreakpoints = Set.from(ctrl.breakpoints);
    for (final l in _lastKnownBreakpoints.difference(lines)) {
      if (ctrl.hasBreakpoint(l)) ctrl.toggleBreakpoint(l);
    }
    for (final l in lines.difference(_lastKnownBreakpoints)) {
      if (!ctrl.hasBreakpoint(l)) ctrl.toggleBreakpoint(l);
    }
    _lastKnownBreakpoints = Set.from(ctrl.breakpoints);
  }

  void _onControllerChanged() {
    if (_applyingLineStyles) return;
    final ctrl = widget.file.controller;
    if (ctrl == null) return;
    final current = Set<int>.from(ctrl.breakpoints);
    if (current.length == _lastKnownBreakpoints.length &&
        current.containsAll(_lastKnownBreakpoints)) return;
    _lastKnownBreakpoints = current;
    context.read<DebugProvider>().setBreakpointsForFile(widget.file.path, current);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (widget.file.controller == null) {
      if (widget.file.isImage) return _ImageViewer(file: widget.file);
      return Center(child: CircularProgressIndicatorM3E());
    }

    final ctrl = widget.file.controller!;

    if (widget.configureProps != null) {
      widget.configureProps!(ctrl.props);
    }

    final effectiveTheme = (widget.fontSize != null || widget.fontFamily != null)
        ? (widget.editorTheme ?? QuillThemeDark.build()).copyWith(
            fontSize: widget.fontSize,
            fontFamily: widget.fontFamily,
          )
        : widget.editorTheme;

    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): () =>
            context.read<EditorProvider>().saveActiveFile(),
      },
      child: Focus(
        autofocus: false,
        child: Column(
          children: [
            Expanded(
              // RepaintBoundary: editor cursor blink, syntax highlighting and
              // scrolling repaints stay within this boundary and don't bubble
              // up to parent widgets (file tree, status bar, terminal, etc.).
              child: RepaintBoundary(
                child: QuillCodeEditor(
                  controller: ctrl,
                  onChanged: (_) => context.read<EditorProvider>().markDirty(),
                  onSave: () => context.read<EditorProvider>().saveActiveFile(),
                  lspClient: _ownedLspClient,
                  fileUri: Uri.file(widget.file.path).toString(),
                  theme: effectiveTheme,
                  showSymbolBar: widget.showSymbolBar,
                  // Diagnostic counts now live inside the status bar (part of
                  // QuillCodeEditor) and are tappable to open the Problems panel.
                  onDiagnosticTap: widget.onDiagnosticTap,
                  onScrollDirectionChanged: widget.onScrollDirectionChanged,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


class _WelcomePane extends StatelessWidget {
  const _WelcomePane();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surface,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                Image.asset('assets/logo.png',
                    width: 100,
                    height: 100,
                    fit: BoxFit.cover,
                    color: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.color),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14, height: 1.6),
                children: [
                  const TextSpan(text: 'Swipe right for '),
                  TextSpan(
                    text: 'files',
                    style: TextStyle(
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: cs.primary),
                  ),
                  const TextSpan(text: '.\nSwipe up for '),
                  TextSpan(
                    text: 'build output',
                    style: TextStyle(
                        color: cs.primary,
                        decoration: TextDecoration.underline,
                        decorationColor: cs.primary),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Image viewer ─────────────────────────────────────────────────────────────

class _ImageViewer extends StatelessWidget {
  final OpenFile file;
  const _ImageViewer({required this.file});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ext = file.extension.toLowerCase();

    Widget image;
    if (ext == 'svg') {
      image = SvgPicture.file(
        File(file.path),
        placeholderBuilder: (_) => Center(
          child: CircularProgressIndicatorM3E(),
        ),
        fit: BoxFit.contain,
      );
    } else {
      image = Image.file(
        File(file.path),
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, _) {
          if (frame == null) {
            return Center(child: CircularProgressIndicatorM3E());
          }
          return child;
        },
        errorBuilder: (context, error, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, size: 48, color: cs.onSurfaceVariant),
              const SizedBox(height: 8),
              Text('Cannot load image', style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    return Container(
      color: cs.surfaceContainerLow,
      child: Stack(
        children: [
          Center(child: image),
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  file.name,
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
