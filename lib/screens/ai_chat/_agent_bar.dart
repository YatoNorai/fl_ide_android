part of '../ai_chat_drawer.dart';

// ── Agent + model bar ─────────────────────────────────────────────────────────

class _AgentModelBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final chat  = context.watch<ChatProvider>();
    final ai    = context.read<AiProvider>();
    final agent = chat.selectedAgent;

    final (String prov, String _) = ai.geminiKey.isNotEmpty
        ? ('Gemini', ai.geminiModel)
        : ai.claudeKey.isNotEmpty
            ? ('Claude', ai.claudeModel)
            : ai.gptKey.isNotEmpty
                ? ('GPT', ai.gptModel)
                : ai.deepSeekKey.isNotEmpty
                    ? ('DeepSeek', ai.deepSeekModel)
                    : ('Sem API', '');

    return InkWell(
      onTap: () => _showAgentSheet(context, chat, ai),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: Color(agent.colorValue),
                child: Text(agent.name[0],
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(agent.name,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(prov,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.onSecondaryContainer)),
              ),
              const SizedBox(width: 4),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  void _showAgentSheet(BuildContext context, ChatProvider chat, AiProvider ai) {
    final cs = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      backgroundColor: cs.surfaceContainerLow,
      builder: (ctx) {
        final maxHeight = MediaQuery.of(ctx).size.height * 0.7;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(top: 10, bottom: 4),
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                  child: Text('Selecionar Agente',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: cs.onSurface)),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(bottom: 8),
                    children: ai.agents.map((a) {
                      final selected = a.id == chat.selectedAgent.id;
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          radius: 16,
                          backgroundColor: Color(a.colorValue),
                          child: Text(a.name[0],
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12)),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(a.name,
                                  style: TextStyle(
                                      fontSize: 13, color: cs.onSurface)),
                            ),
                            if (a.isOrchestrator)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: cs.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('multi-agente',
                                    style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: cs.onTertiaryContainer)),
                              ),
                          ],
                        ),
                        subtitle: Text(a.focus,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                        trailing: selected
                            ? Icon(Icons.check_rounded,
                                color: cs.primary, size: 18)
                            : null,
                        onTap: () {
                          chat.selectAgent(a);
                          Navigator.pop(ctx);
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
