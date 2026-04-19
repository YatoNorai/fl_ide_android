part of '../ai_chat_drawer.dart';

// ── AI message ────────────────────────────────────────────────────────────────

class _AiMessage extends StatelessWidget {
  final ChatMessage message;
  final AiAgent agent;
  final Future<void> Function(FileOperation) onExecuteOp;

  const _AiMessage({
    required this.message,
    required this.agent,
    required this.onExecuteOp,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Sub-agent messages (from orchestrator phases) override the avatar
    final bool hasSub = message.subAgentId.isNotEmpty;
    final Color avatarColor = hasSub
        ? Color(message.subAgentColor)
        : Color(agent.colorValue);
    final String avatarLabel = hasSub
        ? message.subAgentLabel
        : agent.name;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub-agent phase chip (e.g. "Arquiteto · Fase 1")
          if (hasSub)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, left: 2),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: avatarColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    avatarLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: avatarColor,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: avatarColor,
                child: Text(avatarLabel[0],
                    style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!hasSub)
                      Text(agent.name,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant)),
                    if (!hasSub) const SizedBox(height: 3),
                    if (message.isThinking && message.text.isEmpty)
                      const _ThinkingDots()
                    else
                      _MessageContent(
                        message: message,
                        onExecuteOp: onExecuteOp,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Thinking animation ────────────────────────────────────────────────────────

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots();
  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // 1350ms = 3 dots × 450ms each; repeat() cycles 0.0→1.0 continuously.
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1350))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _ctrl,
      // child is built once and reused every frame — avoids rebuilding
      // the Icon subtree on every animation tick (~60×/sec).
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.more_horiz_rounded, size: 16, color: cs.primary),
        const SizedBox(width: 4),
      ]),
      builder: (_, child) {
        // Map 0.0-1.0 → 1-3 dots (1 dot at start, 3 at peak, cycles back).
        final dotCount = (_ctrl.value * 3).ceil().clamp(1, 3);
        final dots = '.' * dotCount;
        // Pulse opacity in sync with the same controller value.
        final opacity = 0.4 + _ctrl.value * 0.6;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(opacity: opacity, child: child),
            Text(
              'Pensando$dots',
              style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontSize: 12,
                  fontStyle: FontStyle.italic),
            ),
          ],
        );
      },
    );
  }
}
