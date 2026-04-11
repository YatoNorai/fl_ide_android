part of '../ai_chat_drawer.dart';

// ── File operation approval card ──────────────────────────────────────────────

class _FileOpCard extends StatefulWidget {
  final FileOperation op;
  final String msgId;
  final Future<void> Function(FileOperation) onExecuteOp;

  const _FileOpCard({
    required this.op,
    required this.msgId,
    required this.onExecuteOp,
  });

  @override
  State<_FileOpCard> createState() => _FileOpCardState();
}

class _FileOpCardState extends State<_FileOpCard> {

  bool _executing = false;

  @override
  void initState() {
    super.initState();
    // Auto-execute terminal commands that the user has set to always accept.
    if (widget.op.type == FileOpType.terminal &&
        widget.op.status == FileOpStatus.pending &&
        widget.op.command != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final chat = context.read<ChatProvider>();
        if (chat.isAlwaysAccepted(widget.op.command!)) {
          _accept(context, chat);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final chat = context.watch<ChatProvider>();
    final op   = widget.op;
    final status = op.status;

    // Colour band by status
    final (Color band, Color bg) = switch (status) {
      FileOpStatus.accepted => (cs.primary, cs.primaryContainer.withValues(alpha: 0.2)),
      FileOpStatus.rejected => (cs.error, cs.errorContainer.withValues(alpha: 0.15)),
      _                     => (cs.outline, cs.surfaceContainerLow),
    };

    // Icon for op type
    final opIcon = switch (op.type) {
      FileOpType.write    => Icons.edit_document,
      FileOpType.delete   => Icons.delete_outline_rounded,
      FileOpType.rename   => Icons.drive_file_rename_outline_rounded,
      FileOpType.mkdir    => Icons.create_new_folder_outlined,
      FileOpType.terminal => Icons.terminal_rounded,
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: band.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
            decoration: BoxDecoration(
              color: band.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                topRight: Radius.circular(10),
              ),
            ),
            child: Row(
              children: [
                Icon(opIcon, size: 15, color: band),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(op.opLabel,
                          style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                              fontWeight: FontWeight.w500)),
                      Text(op.type == FileOpType.terminal
                              ? (op.command ?? op.path)
                              : op.type == FileOpType.rename
                                  ? '${op.path} → ${op.newPath}'
                                  : op.path,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurface),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                // Status badge
                if (status != FileOpStatus.pending)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: band,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      status == FileOpStatus.accepted ? 'Aceito' : 'Recusado',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),

          // ── Code preview (write ops) ─────────────────────────
          if (op.type == FileOpType.write && op.content != null)
            _CodePreview(code: op.content!, language: op.language ?? ''),

          // ── Command output (terminal ops after execution) ────
          if (op.type == FileOpType.terminal &&
              op.commandOutput != null &&
              op.commandOutput!.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                border: Border(
                  top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
                ),
              ),
              child: SelectableText(
                op.commandOutput!,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),

          // ── Action buttons (pending only) ────────────────────
          if (status == FileOpStatus.pending)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: _executing
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: cs.primary),
                          ),
                          const SizedBox(width: 8),
                          Text('Executando…',
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            // Accept all button
                            TextButton.icon(
                              onPressed: () => _acceptAll(context, chat),
                              icon: const Icon(Icons.done_all_rounded, size: 14),
                              label: const Text('Aceitar tudo',
                                  style: TextStyle(fontSize: 12)),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.primary,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                              ),
                            ),
                            const Spacer(),
                            // Reject
                            OutlinedButton(
                              onPressed: () => chat.setOperationStatus(
                                  widget.msgId, op.id, FileOpStatus.rejected),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.error,
                                side: BorderSide(
                                    color: cs.error.withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                minimumSize: const Size(0, 32),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              child: const Text('Recusar'),
                            ),
                            const SizedBox(width: 8),
                            // Accept
                            FilledButton(
                              onPressed: () => _accept(context, chat),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 4),
                                minimumSize: const Size(0, 32),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              child: const Text('Aceitar'),
                            ),
                          ],
                        ),
                        // "Aceitar sempre" — only for terminal commands
                        if (op.type == FileOpType.terminal &&
                            op.command != null &&
                            !chat.isAlwaysAccepted(op.command!))
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () {
                                chat.addAlwaysAcceptCmd(op.command!);
                                _accept(context, chat);
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: cs.onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 2),
                                textStyle: const TextStyle(fontSize: 11),
                              ),
                              child: const Text('Aceitar sempre este comando'),
                            ),
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }

  Future<void> _accept(BuildContext ctx, ChatProvider chat) async {
    if (_executing) return;
    setState(() => _executing = true);
    chat.setOperationStatus(widget.msgId, widget.op.id, FileOpStatus.accepted);
    try {
      await widget.onExecuteOp(widget.op);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Erro ao executar operação: $e')),
        );
        chat.setOperationStatus(
            widget.msgId, widget.op.id, FileOpStatus.rejected);
      }
    } finally {
      if (mounted) setState(() => _executing = false);
    }
  }

  Future<void> _acceptAll(BuildContext ctx, ChatProvider chat) async {
    final conv = chat.activeConversation;
    if (conv == null) return;
    final msg = conv.messages.firstWhere((m) => m.id == widget.msgId,
        orElse: () => const ChatMessage(id: '', isUser: false, text: ''));
    if (msg.id.isEmpty) return;

    for (final o in msg.operations) {
      if (o.status != FileOpStatus.pending) continue;
      chat.setOperationStatus(widget.msgId, o.id, FileOpStatus.accepted);
      try {
        await widget.onExecuteOp(o);
      } catch (e) {
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(content: Text('Erro em ${o.path}: $e')),
          );
          chat.setOperationStatus(widget.msgId, o.id, FileOpStatus.rejected);
        }
      }
    }
  }
}

// ── Code preview inside operation card ───────────────────────────────────────

class _CodePreview extends StatelessWidget {
  final String code;
  final String language;
  const _CodePreview({required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final isDark = cs.brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : cs.surfaceContainerHighest;

    // Show at most 40 lines in preview
    final lines  = code.split('\n');
    final preview = lines.length > 40
        ? '${lines.take(40).join('\n')}\n… (+${lines.length - 40} linhas)'
        : code;

    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.symmetric(
          horizontal: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: SelectableText(
            preview,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11.5,
              color: isDark ? const Color(0xFFD4D4D4) : cs.onSurface,
              height: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
