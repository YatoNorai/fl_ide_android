part of '../ai_chat_drawer.dart';

// ── User message ──────────────────────────────────────────────────────────────

enum _EditStage { none, editing, confirming }

class _UserMessage extends StatefulWidget {
  final ChatMessage message;
  final Future<void> Function(ChatMessage, String, bool) onResend;

  const _UserMessage({required this.message, required this.onResend});

  @override
  State<_UserMessage> createState() => _UserMessageState();
}

class _UserMessageState extends State<_UserMessage> {
  _EditStage _stage = _EditStage.none;
  bool _showActions = false;
  late final TextEditingController _editCtrl;
  bool _textChanged = false;

  @override
  void initState() {
    super.initState();
    _editCtrl = TextEditingController(text: widget.message.text);
    _editCtrl.addListener(() {
      final changed = _editCtrl.text != widget.message.text;
      if (changed != _textChanged) setState(() => _textChanged = changed);
    });
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  void _cancel() {
    _editCtrl.text = widget.message.text;
    setState(() {
      _stage = _EditStage.none;
      _showActions = false;
      _textChanged = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_stage == _EditStage.none) {
      return _buildBubble(cs);
    } else {
      return _buildEditField(cs);
    }
  }

  // ── Normal bubble (tap to show/hide actions) ──────────────────────────────
  Widget _buildBubble(ColorScheme cs) {
    return GestureDetector(
      onTap: () => setState(() => _showActions = !_showActions),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Action icons appear only after tapping the bubble
            if (_showActions) ...[
              _IconAction(
                icon: Icons.copy_outlined,
                tooltip: 'Copiar',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: widget.message.text));
                  setState(() => _showActions = false);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mensagem copiada'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
              ),
              const SizedBox(width: 4),
              _IconAction(
                icon: Icons.edit_outlined,
                tooltip: 'Editar',
                onTap: () => setState(() {
                  _showActions = false;
                  _stage = _EditStage.editing;
                }),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(18),
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                  child: Text(widget.message.text,
                      style: TextStyle(
                          color: cs.onPrimaryContainer,
                          fontSize: 13,
                          height: 1.45)),
                ),
              ),
            ],
          ),
        ),
    );
  }

  // ── Edit field ─────────────────────────────────────────────────────────────
  Widget _buildEditField(ColorScheme cs) {
    final isConfirming = _stage == _EditStage.confirming;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // TextField
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: cs.primary.withValues(alpha: 0.5)),
            ),
            child: TextField(
              controller: _editCtrl,
              autofocus: true,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              style: TextStyle(color: cs.onSurface, fontSize: 13),
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.all(12),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Buttons
          if (!isConfirming)
            Row(
              children: [
                // Cancel
                TextButton(
                  onPressed: _cancel,
                  child: Text('Cancelar',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
                const Spacer(),
                // Update (disabled until text changes)
                FilledButton(
                  onPressed: _textChanged
                      ? () => setState(() => _stage = _EditStage.confirming)
                      : null,
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Atualizar'),
                ),
              ],
            )
          else
            // Confirming stage: [Cancel] [Restaurar+Atualizar] [Confirmar]
            Row(
              children: [
                TextButton(
                  onPressed: _cancel,
                  child: Text('Cancelar',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ),
                const Spacer(),
                // Restore + Update
                OutlinedButton.icon(
                  onPressed: () async {
                    _cancel();
                    await widget.onResend(
                        widget.message, _editCtrl.text.trim(), true);
                  },
                  icon: const Icon(Icons.restore_rounded, size: 14),
                  label: const Text('Restaurar+Enviar',
                      style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    side: BorderSide(color: cs.tertiary.withValues(alpha: 0.6)),
                    foregroundColor: cs.tertiary,
                  ),
                ),
                const SizedBox(width: 6),
                // Confirm update
                FilledButton(
                  onPressed: () async {
                    final newText = _editCtrl.text.trim();
                    _cancel();
                    await widget.onResend(widget.message, newText, false);
                  },
                  style: FilledButton.styleFrom(
                    textStyle: const TextStyle(fontSize: 12),
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _IconAction({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}
