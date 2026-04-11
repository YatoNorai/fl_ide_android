part of '../ai_chat_drawer.dart';

// ── Agent + model bar ─────────────────────────────────────────────────────────

class _AgentModelBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final chat  = context.watch<ChatProvider>();
    final ai    = context.watch<AiProvider>();
    final agent = chat.selectedAgent;

    final prov  = ai.effectiveProvider;
    final model = switch (prov) {
      'gemini'   => ai.geminiModel,
      'claude'   => ai.claudeModel,
      'gpt'      => ai.gptModel,
      'deepseek' => ai.deepSeekModel,
      _          => '',
    };
    final provLabel = switch (prov) {
      'gemini'   => 'Gemini',
      'claude'   => 'Claude',
      'gpt'      => 'GPT',
      'deepseek' => 'DeepSeek',
      _          => 'Sem API',
    };

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
              if (model.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    model.length > 18 ? '${model.substring(0, 18)}…' : model,
                    style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: cs.onPrimaryContainer),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(provLabel,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: cs.onErrorContainer)),
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

  void _showAgentSheet(BuildContext ctx, ChatProvider chat, AiProvider ai) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider.value(
        value: chat,
        child: ChangeNotifierProvider.value(
          value: ai,
          child: _AgentSheet(initialAgent: chat.selectedAgent),
        ),
      ),
    );
  }
}

// ── Full agent/model sheet ────────────────────────────────────────────────────

class _AgentSheet extends StatefulWidget {
  final AiAgent initialAgent;
  const _AgentSheet({required this.initialAgent});

  @override
  State<_AgentSheet> createState() => _AgentSheetState();
}

class _AgentSheetState extends State<_AgentSheet> {
  late AiAgent _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialAgent;
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final chat = context.watch<ChatProvider>();
    final ai   = context.watch<AiProvider>();

    final prov  = ai.effectiveProvider;
    final models = switch (prov) {
      'gemini'   => kGeminiModels,
      'claude'   => kClaudeModels,
      'gpt'      => kGptModels,
      'deepseek' => kDeepSeekModels,
      _          => <String>[],
    };
    final currentModel = switch (prov) {
      'gemini'   => ai.geminiModel,
      'claude'   => ai.claudeModel,
      'gpt'      => ai.gptModel,
      'deepseek' => ai.deepSeekModel,
      _          => '',
    };

    // Available providers (only those with a configured key)
    final providers = <({String id, String label})>[
      if (ai.geminiKey.isNotEmpty)   (id: 'gemini',   label: 'Gemini'),
      if (ai.claudeKey.isNotEmpty)   (id: 'claude',   label: 'Claude'),
      if (ai.gptKey.isNotEmpty)      (id: 'gpt',      label: 'GPT'),
      if (ai.deepSeekKey.isNotEmpty) (id: 'deepseek', label: 'DeepSeek'),
    ];

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) => Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 4),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // ── Agentes ──────────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('Agente',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: cs.primary)),
                ),
                ...ai.agents.map((a) {
                  final isSelected = a.id == _selected.id;
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
                    title: Row(children: [
                      Expanded(
                        child: Text(a.name,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.normal,
                                color: cs.onSurface)),
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
                    ]),
                    subtitle: Text(a.focus,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                    trailing: isSelected
                        ? Icon(Icons.check_rounded, color: cs.primary, size: 18)
                        : null,
                    onTap: () {
                      setState(() => _selected = a);
                      chat.selectAgent(a);
                    },
                  );
                }),

                // ── Sub-agentes do orquestrador ───────────────────────────────
                if (_selected.isOrchestrator) ...[
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text('Sub-agentes do Orquestrador',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.primary)),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Ative ou desative os agentes que o Orquestrador irá usar.',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                    ),
                  ),
                  ..._buildSubAgentToggles(context, ai, chat),
                ],

                // ── Provedor ──────────────────────────────────────────────────
                if (providers.isNotEmpty) ...[
                  const Divider(height: 24),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                    child: Text('Provedor',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.primary)),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: providers.map((p) {
                        final active = ai.effectiveProvider == p.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(p.label),
                            selected: active,
                            onSelected: (_) => ai.setActiveProvider(p.id),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // ── Modelo ────────────────────────────────────────────────────
                if (models.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: Text('Modelo',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                            color: cs.primary)),
                  ),
                  ...models.map((m) {
                    final isActive = m == currentModel;
                    return ListTile(
                      dense: true,
                      title: Text(m,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: cs.onSurface)),
                      trailing: isActive
                          ? Icon(Icons.check_rounded,
                              color: cs.primary, size: 18)
                          : null,
                      onTap: () {
                        switch (prov) {
                          case 'gemini':   ai.setGeminiModel(m);
                          case 'claude':   ai.setClaudeModel(m);
                          case 'gpt':      ai.setGptModel(m);
                          case 'deepseek': ai.setDeepSeekModel(m);
                        }
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSubAgentToggles(
      BuildContext context, AiProvider ai, ChatProvider chat) {
    final cs = Theme.of(context).colorScheme;
    // All non-orchestrator agents can be used as sub-agents
    final subCandidates = ai.agents.where((a) => !a.isOrchestrator).toList();

    return subCandidates.map((a) {
      final enabledIds = _selected.enabledSubAgentIds;
      // Empty list = all enabled (default)
      final isEnabled = enabledIds.isEmpty || enabledIds.contains(a.id);

      return SwitchListTile(
        dense: true,
        secondary: CircleAvatar(
          radius: 14,
          backgroundColor: Color(a.colorValue),
          child: Text(a.name[0],
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 11)),
        ),
        title: Text(a.name,
            style: TextStyle(fontSize: 13, color: cs.onSurface)),
        subtitle: Text(a.focus,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        value: isEnabled,
        onChanged: (val) {
          // Build the new enabled list
          List<String> newIds;
          if (enabledIds.isEmpty) {
            // Was "all" — explicitly list everyone except this one if disabling
            newIds = val
                ? subCandidates.map((x) => x.id).toList()
                : subCandidates
                    .where((x) => x.id != a.id)
                    .map((x) => x.id)
                    .toList();
          } else {
            newIds = val
                ? [...enabledIds, a.id]
                : enabledIds.where((id) => id != a.id).toList();
          }
          // If all are enabled, normalise back to empty (= all)
          if (newIds.length == subCandidates.length) newIds = [];
          final updated = _selected.copyWith(enabledSubAgentIds: newIds);
          setState(() => _selected = updated);
          ai.updateAgent(updated);
          chat.selectAgent(updated);
        },
      );
    }).toList();
  }
}
