import 'package:core/core.dart';
import 'package:dap_client/dap_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:provider/provider.dart';
import 'package:quill_code/quill_code.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/editor_provider.dart';
import 'editor_tab_bar.dart';

class EditorArea extends StatelessWidget {
  final EditorTheme? editorTheme;
  final void Function(EditorProps props)? configureProps;
  final bool showSymbolBar;
  final double? fontSize;
  final String? fontFamily;
  final bool showTabBar;
  final bool forBottomPanel;

  const EditorArea({
    super.key,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
    this.showTabBar = true,
    this.forBottomPanel = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        final active = forBottomPanel
            ? editor.bottomActiveFile
            : editor.topActiveFile;

        return Column(
          children: [
            if (showTabBar) ...[
              const EditorTabBar(),
              const Divider(height: 1, thickness: 1),
            ],
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
                    )
                  : _MainContent(
                      file: active,
                      editorTheme: editorTheme,
                      configureProps: configureProps,
                      showSymbolBar: showSymbolBar,
                      fontSize: fontSize,
                      fontFamily: fontFamily,
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

  const _MainContent({
    required this.file,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
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

  const _EditorContent({
    required this.file,
    required this.forBottomPanel,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
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

  const _ActiveEditor({
    required this.file,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
    this.forBottomPanel = false,
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
      widget.file.controller?.detachLsp();
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
          // Wire onError before the process starts so early stderr/crashes
          // are surfaced in the UI rather than silently swallowed.
          onError: (msg) {
            if (mounted) context.read<LspProvider>().setError(msg);
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
      return;
    }

    _ownedLspClient = client;
    final langId = cfg.languageId;
    await file.controller?.attachLsp(
      client,
      uri:        Uri.file(file.path).toString(),
      languageId: langId,
    );
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
        final langId = _cachedLspConfig!.languageId;
        final newUri = Uri.file(widget.file.path).toString();
        old.file.controller?.detachLsp();
        widget.file.controller?.attachLsp(
          client,
          uri:        newUri,
          languageId: langId,
        );
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
      return Center(child: CircularProgressIndicator(color: cs.primary));
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
                  lspClient: _ownedLspClient,
                  fileUri: Uri.file(widget.file.path).toString(),
                  theme: effectiveTheme,
                  showSymbolBar: widget.showSymbolBar,
                ),
              ),
            ),
            _DiagnosticsBar(controller: ctrl),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticsBar extends StatelessWidget {
  final QuillCodeController controller;

  const _DiagnosticsBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final cs  = Theme.of(context).colorScheme;
    final ide = Theme.of(context).extension<IdeColors>() ?? IdeColors.light;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final all = controller.diagnostics.all;
        if (all.isEmpty) return const SizedBox.shrink();

        final errors   = all.where((d) => d.severity == DiagnosticSeverity.error).length;
        final warnings = all.where((d) => d.severity == DiagnosticSeverity.warning).length;
        final infos    = all.where((d) => d.severity == DiagnosticSeverity.info).length;

        return Container(
          height: 24,
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              if (errors > 0) ...[
                Icon(Icons.error_outline, size: 14, color: cs.error),
                const SizedBox(width: 3),
                Text('$errors', style: TextStyle(color: cs.error, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
              ],
              if (warnings > 0) ...[
                Icon(Icons.warning_amber_outlined, size: 14, color: ide.warning),
                const SizedBox(width: 3),
                Text('$warnings', style: TextStyle(color: ide.warning, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
              ],
              if (infos > 0) ...[
                Icon(Icons.info_outline, size: 14, color: cs.primary),
                const SizedBox(width: 3),
                Text('$infos', style: TextStyle(color: cs.primary, fontSize: 11)),
              ],
            ],
          ),
        );
      },
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
