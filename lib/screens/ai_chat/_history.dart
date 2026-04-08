part of '../ai_chat_drawer.dart';

// ── History view ──────────────────────────────────────────────────────────────

class _HistoryView extends StatelessWidget {
  final VoidCallback onSelect;
  final Future<void> Function(ProjectSnapshot) onRestore;

  const _HistoryView({
    super.key,
    required this.onSelect,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    // Select only the data needed — avoids rebuilding history on every
    // streaming token (isStreaming, active message text, etc.).
    final convs = context.select<ChatProvider, List<ChatConversation>>(
      (c) => c.conversations,
    );
    final snaps = context.select<ChatProvider, List<ProjectSnapshot>>(
      (c) => c.snapshots,
    );
    final activeId = context.select<ChatProvider, String?>(
      (c) => c.activeConversation?.id,
    );

    if (convs.isEmpty && snaps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline_rounded, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Sem conversas ainda',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      children: [
        // Conversations
        if (convs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Text('Conversas',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),
          ...convs.map((conv) {
            final isActive = conv.id == activeId;
            return _ConvTile(
              conv: conv,
              isActive: isActive,
              onTap: () {
                context.read<ChatProvider>().openConversation(conv);
                onSelect();
              },
            );
          }),
        ],

        // Snapshots
        if (snaps.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Text('Versões salvas (restaurar antes da mensagem)',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant)),
          ),
          ...snaps.map((snap) => _SnapshotTile(
                snap: snap,
                onRestore: () => onRestore(snap),
              )),
        ],
      ],
    );
  }
}

class _ConvTile extends StatelessWidget {
  final ChatConversation conv;
  final bool isActive;
  final VoidCallback onTap;
  const _ConvTile({required this.conv, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: isActive
              ? BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(10),
                )
              : null,
          child: Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: Color(conv.agent.colorValue),
                child: Text(conv.agent.name[0],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(conv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: cs.onSurface)),
                    Text(conv.agent.name,
                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnapshotTile extends StatelessWidget {
  final ProjectSnapshot snap;
  final VoidCallback onRestore;
  const _SnapshotTile({required this.snap, required this.onRestore});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final time = snap.timestamp;
    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onRestore,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: cs.tertiaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.restore_rounded,
                    size: 16, color: cs.onTertiaryContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Antes da mensagem ${snap.userMessageIndex}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface),
                    ),
                    Text(
                      '"${snap.messagePreview}"  •  $label  •  ${snap.fileBackups.length} arquivo(s)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
