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
  const EditorArea({super.key, this.editorTheme});

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        return Column(
          children: [
            const EditorTabBar(),
            Expanded(
              child: editor.activeFile == null
                  ? const _WelcomePane()
                  : _ActiveEditor(
                      file: editor.activeFile!, editorTheme: editorTheme),
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

  const _ActiveEditor({required this.file, this.editorTheme});

  @override
  Widget build(BuildContext context) {
    if (file.controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.darkAccent),
      );
    }

    final lspProvider = context.watch<LspProvider>();

    return CallbackShortcuts(
      bindings: {
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): () =>
            context.read<EditorProvider>().saveActiveFile(),
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _Breadcrumbs(path: file.path),
            Expanded(
              child: Stack(
                children: [
                  QuillCodeEditor(
                    controller: file.controller!,
                    onChanged: (_) =>
                        context.read<EditorProvider>().markDirty(),
                    // Pass LSP config if server is running
                    lspConfig: lspProvider.lspConfig,
                    fileUri: Uri.file(file.path).toString(),
                    theme: editorTheme,
                  ),
                  // Inline diagnostics summary bar
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _DiagnosticsBar(controller: file.controller!),
                  ),
                ],
              ),
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
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final all = controller.diagnostics.all;
        if (all.isEmpty) return const SizedBox.shrink();

        final hasError =
            all.any((d) => d.severity == DiagnosticSeverity.error);

        return Container(
          height: 24,
          color: AppTheme.darkTabBar,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                hasError ? Icons.error_outline : Icons.warning_amber_outlined,
                size: 14,
                color: hasError ? AppTheme.darkError : AppTheme.darkWarning,
              ),
              const SizedBox(width: 6),
              Text(
                '${all.length} problem${all.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: AppTheme.darkTextMuted, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  final String path;

  const _Breadcrumbs({required this.path});

  @override
  Widget build(BuildContext context) {
    final parts = path.replaceAll('\\', '/').split('/');
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      color: AppTheme.darkTabBar,
      child: Row(
        children: parts.asMap().entries.map((e) {
          final isLast = e.key == parts.length - 1;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                e.value,
                style: TextStyle(
                  color: isLast ? AppTheme.darkText : AppTheme.darkTextMuted,
                  fontSize: 12,
                ),
              ),
              if (!isLast)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right,
                      size: 14, color: AppTheme.darkTextMuted),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _WelcomePane extends StatelessWidget {
  const _WelcomePane();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkBg,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('FL IDE',
                style: TextStyle(
                    color: AppTheme.darkText,
                    fontSize: 26,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            RichText(
              textAlign: TextAlign.center,
              text: const TextSpan(
                style: TextStyle(color: AppTheme.darkTextMuted, fontSize: 14, height: 1.6),
                children: [
                  TextSpan(text: 'Swipe right for '),
                  TextSpan(
                    text: 'files',
                    style: TextStyle(
                        color: AppTheme.darkAccent,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.darkAccent),
                  ),
                  TextSpan(text: '.\nSwipe up for '),
                  TextSpan(
                    text: 'build output',
                    style: TextStyle(
                        color: AppTheme.darkAccent,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.darkAccent),
                  ),
                  TextSpan(text: '.'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

