part of '../ai_chat_drawer.dart';

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  final bool showHistory;
  final VoidCallback onToggleHistory;

  const _Header({
    required this.onClose,
    required this.showHistory,
    required this.onToggleHistory,
  });

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final chat = context.watch<ChatProvider>();
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: cs.onSurface),
            onPressed: onClose,
            tooltip: 'Fechar',
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          ),
          const SizedBox(width: 2),
          Icon(Icons.auto_awesome_rounded, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            'Agente IA',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          // Auto-accept toggle
          Tooltip(
            message: chat.autoAccept
                ? 'Aceitar alterações: sempre'
                : 'Aceitar alterações: pedir',
            child: IconButton(
              icon: Icon(
                chat.autoAccept
                    ? Icons.check_circle_rounded
                    : Icons.check_circle_outline_rounded,
                size: 20,
                color: chat.autoAccept ? cs.primary : cs.onSurface,
              ),
              onPressed: () => chat.setAutoAccept(!chat.autoAccept),
              constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_comment_outlined, size: 19, color: cs.onSurface),
            onPressed: () => chat.newConversation(),
            tooltip: 'Nova conversa',
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          ),
          IconButton(
            icon: Icon(
              Icons.history_rounded,
              size: 20,
              color: showHistory ? cs.primary : cs.onSurface,
            ),
            onPressed: onToggleHistory,
            tooltip: 'Histórico',
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}
