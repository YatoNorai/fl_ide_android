import 'package:core/core.dart';
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

  const EditorArea({
    super.key,
    this.editorTheme,
    this.configureProps,
    this.showSymbolBar = true,
    this.fontSize,
    this.fontFamily,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        return Column(
          children: [
            const EditorTabBar(),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: editor.activeFile == null
                  ? const _WelcomePane()
                  : _ActiveEditor(
                      file: editor.activeFile!,
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


class _ActiveEditor extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (file.controller == null) {
      return Center(
        child: CircularProgressIndicator(color: cs.primary),
      );
    }

    // Apply caller-supplied props (e.g. from SettingsProvider)
    if (configureProps != null) {
      configureProps!(file.controller!.props);
    }

    // Apply font size and font family overrides to theme
    final effectiveTheme = (fontSize != null || fontFamily != null)
        ? (editorTheme ?? QuillThemeDark.build()).copyWith(
            fontSize: fontSize,
            fontFamily: fontFamily,
          )
        : editorTheme;

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
                controller: file.controller!,
                onChanged: (_) =>
                    context.read<EditorProvider>().markDirty(),
                lspConfig: lspProvider.lspConfig,
                fileUri: Uri.file(file.path).toString(),
                theme: effectiveTheme,
                showSymbolBar: showSymbolBar,
              ),
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _DiagnosticsBar(controller: file.controller!),
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

