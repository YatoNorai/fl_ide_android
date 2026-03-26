import 'package:core/core.dart';
import 'package:dap_client/dap_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:provider/provider.dart';
import 'package:quill_code/quill_code.dart';

import '../providers/editor_provider.dart';
import 'editor_tab_bar.dart';

class EditorArea extends StatelessWidget {
  final EditorTheme? editorTheme;
  /// Applied to the controller's props before each build.
  final void Function(EditorProps props)? configureProps;
  /// Whether to show the symbol input bar (mobile keyboard helpers).
  final bool showSymbolBar;
  /// Font size override applied to [editorTheme].
  final double? fontSize;
  /// Font family override applied to [editorTheme].
  final String? fontFamily;
  /// Whether to show the [EditorTabBar] at the top.
  /// Set to false when the caller provides its own tab bar (e.g. bottom panel).
  final bool showTabBar;
  /// When true this area only renders files whose [OpenFile.inBottomPanel] is
  /// true; when false (default) it only renders top-panel files.
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
        final active = editor.activeFile;
        final showEditor = active != null &&
            (forBottomPanel ? active.inBottomPanel : !active.inBottomPanel);
        return Column(
          children: [
            if (showTabBar) ...[
              const EditorTabBar(),
              const Divider(height: 1, thickness: 1),
            ],
            Expanded(
              child: showEditor
                  ? _ActiveEditor(
                      file: active,
                      editorTheme: editorTheme,
                      configureProps: configureProps,
                      showSymbolBar: showSymbolBar,
                      fontSize: fontSize,
                      fontFamily: fontFamily,
                    )
                  : const _WelcomePane(),
            ),
          ],
        );
      },
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

  const _ActiveEditor({
    required this.file,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
  });

  @override
  State<_ActiveEditor> createState() => _ActiveEditorState();
}

class _ActiveEditorState extends State<_ActiveEditor> {
  Set<int> _lastKnownBreakpoints = {};
  DebugProvider? _debugProvider;
  // Guard: prevents _onControllerChanged from reacting to setLineStyles calls,
  // which also notify listeners but don't change breakpoints.
  bool _applyingLineStyles = false;

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
    // Subscribe directly to DebugProvider so we can call setLineStyles
    // outside of build() — calling it inside build causes setState-during-build.
    final newDbg = Provider.of<DebugProvider>(context, listen: false);
    if (newDbg != _debugProvider) {
      _debugProvider?.removeListener(_applyDebugLine);
      _debugProvider = newDbg;
      _debugProvider!.addListener(_applyDebugLine);
    }
  }

  @override
  void didUpdateWidget(_ActiveEditor old) {
    super.didUpdateWidget(old);
    if (old.file.path != widget.file.path) {
      old.file.controller?.removeListener(_onControllerChanged);
      widget.file.controller?.addListener(_onControllerChanged);
      _syncBreakpointsIn();
      _applyDebugLine();
    }
  }

  @override
  void dispose() {
    widget.file.controller?.removeListener(_onControllerChanged);
    _debugProvider?.removeListener(_applyDebugLine);
    super.dispose();
  }

  /// Apply or clear the current-line highlight based on debug state.
  /// Called from the DebugProvider listener — never from build().
  void _applyDebugLine() {
    if (!mounted) return;
    final ctrl = widget.file.controller;
    if (ctrl == null) return;
    final dbg = _debugProvider;
    if (dbg == null) return;
    final stoppedHere = dbg.isPaused &&
        dbg.stoppedFile == widget.file.path &&
        dbg.stoppedLine != null;
    // Guard against the re-entrant loop before calling setLineStyles.
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

  /// Sync breakpoints from DebugProvider → editor controller.
  void _syncBreakpointsIn() {
    final ctrl = widget.file.controller;
    if (ctrl == null) return;
    final dbg = context.read<DebugProvider>();
    final lines = dbg.breakpointsForFile(widget.file.path).toSet();
    _lastKnownBreakpoints = Set.from(ctrl.breakpoints);
    // Remove obsolete, add missing
    for (final l in _lastKnownBreakpoints.difference(lines)) {
      if (ctrl.hasBreakpoint(l)) ctrl.toggleBreakpoint(l);
    }
    for (final l in lines.difference(_lastKnownBreakpoints)) {
      if (!ctrl.hasBreakpoint(l)) ctrl.toggleBreakpoint(l);
    }
    _lastKnownBreakpoints = Set.from(ctrl.breakpoints);
  }

  /// Called on any controller change — detect breakpoint changes and sync
  /// them back to DebugProvider.
  void _onControllerChanged() {
    // Ignore notifications triggered by our own setLineStyles call to avoid
    // an infinite loop: setLineStyles → notifyListeners → _onControllerChanged
    // → setBreakpointsForFile → notifyListeners → _applyDebugLine → setLineStyles…
    if (_applyingLineStyles) return;
    final ctrl = widget.file.controller;
    if (ctrl == null) return;
    final current = Set<int>.from(ctrl.breakpoints);
    // Use explicit content comparison — Set == Set uses identity in Dart.
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

    final lspProvider = context.watch<LspProvider>();

    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): () =>
            context.read<EditorProvider>().saveActiveFile(),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: QuillCodeEditor(
                controller: ctrl,
                onChanged: (_) => context.read<EditorProvider>().markDirty(),
                lspConfig: lspProvider.lspConfig,
                fileUri: Uri.file(widget.file.path).toString(),
                theme: effectiveTheme,
                showSymbolBar: widget.showSymbolBar,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _DiagnosticsBar(controller: ctrl),
            ),
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
    final cs = Theme.of(context).colorScheme;
    final ide = Theme.of(context).extension<IdeColors>()!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final all = controller.diagnostics.all;
        if (all.isEmpty) return const SizedBox.shrink();

        final hasError =
            all.any((d) => d.severity == DiagnosticSeverity.error);

        return Container(
          height: 24,
          color: Theme.of(context).scaffoldBackgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.warning_amber_outlined,
                size: 14,
                color: hasError ? cs.error : ide.warning,
              ),
              const SizedBox(width: 6),
              Text(
                '${all.length} problem${all.length == 1 ? '' : 's'}',
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontSize: 11),
              ),
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

