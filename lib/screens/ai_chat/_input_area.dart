part of '../ai_chat_drawer.dart';

// ── Input area ────────────────────────────────────────────────────────────────

class _InputArea extends StatefulWidget {
  final TextEditingController ctrl;
  final FocusNode focusNode;
  final Future<void> Function() onSend;
  final VoidCallback onAttach;
  final bool isBuildingCtx;

  const _InputArea({
    required this.ctrl,
    required this.focusNode,
    required this.onSend,
    required this.onAttach,
    required this.isBuildingCtx,
  });

  @override
  State<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends State<_InputArea> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_onText);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    final has = widget.ctrl.text.isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final chat = context.watch<ChatProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: widget.focusNode.hasFocus
                ? cs.primary.withValues(alpha: 0.6)
                : cs.outlineVariant,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selected context chips
            if (chat.contextPaths.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: chat.contextPaths.map((path) {
                    final name = path.split('/').last.split('\\').last;
                    return Chip(
                      label: Text(name,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSecondaryContainer)),
                      backgroundColor: cs.secondaryContainer,
                      deleteIcon: Icon(Icons.close,
                          size: 13, color: cs.onSecondaryContainer),
                      onDeleted: () => chat.toggleContextPath(path),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              ),

            // Building context indicator
            if (widget.isBuildingCtx)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5, color: cs.primary),
                    ),
                    const SizedBox(width: 8),
                    Text('Lendo arquivos do projeto…',
                        style:
                            TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),

            // Text field
            TextField(
              controller: widget.ctrl,
              focusNode: widget.focusNode,
              enabled: !chat.isStreaming && !widget.isBuildingCtx,
              maxLines: 6,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              keyboardType: TextInputType.multiline,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
              decoration: InputDecoration(
                hintText: chat.isStreaming
                    ? 'Aguardando resposta…'
                    : widget.isBuildingCtx
                        ? 'Lendo projeto…'
                        : 'Pergunte algo…',
                hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              ),
            ),

            // Bottom bar
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 0, 0, 6),
                  child: IconButton(
                    icon: Icon(
                      Icons.attach_file_rounded,
                      size: 18,
                      color: chat.contextPaths.isNotEmpty
                          ? cs.primary
                          : cs.onSurfaceVariant,
                    ),
                    onPressed: widget.onAttach,
                    tooltip: 'Adicionar contexto extra',
                    style: IconButton.styleFrom(
                      minimumSize: const Size(32, 32),
                      padding: const EdgeInsets.all(6),
                    ),
                  ),
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 0, 8, 6),
                  child: _hasText && !chat.isStreaming && !widget.isBuildingCtx
                      ? IconButton.filled(
                          icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                          onPressed: widget.onSend,
                          style: IconButton.styleFrom(
                            minimumSize: const Size(32, 32),
                            padding: const EdgeInsets.all(6),
                            backgroundColor: cs.primary,
                            foregroundColor: cs.onPrimary,
                          ),
                        )
                      : (chat.isStreaming || widget.isBuildingCtx)
                          ? SizedBox(
                              width: 28,
                              height: 28,
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: cs.primary),
                              ),
                            )
                          : IconButton(
                              icon: Icon(Icons.arrow_upward_rounded,
                                  size: 18, color: cs.onSurfaceVariant),
                              onPressed: null,
                              style: IconButton.styleFrom(
                                minimumSize: const Size(32, 32),
                                padding: const EdgeInsets.all(6),
                              ),
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
