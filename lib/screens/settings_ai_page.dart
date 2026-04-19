import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../app.dart' show showThemedDialog;
import '../l10n/app_strings.dart';
import '../models/ai_agent.dart';
import '../providers/ai_provider.dart'
    show AiProvider, kClaudeModels, kDeepSeekModels, kGeminiModels, kGptModels;
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class AiSettingsPage extends StatelessWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final ai = context.watch<AiProvider>();

    return SettingsPageScaffold(
      title: s.ai,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
                  settingsSectionHeader(context,s.apiKeys),
          _apiKeyTile(context,
              label: 'Gemini API Key',
              iconBg: const Color(0xFF1A73E8),
              icon: FontAwesomeIcons.google,
              value: ai.geminiKey,
              onSave: ai.setGeminiKey,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6))),
          _apiKeyTile(context,
              label: 'OpenAI (GPT) API Key',
              iconBg: const Color(0xFF10A37F),
              icon: FontAwesomeIcons.robot,
              value: ai.gptKey,
              onSave: ai.setGptKey,
              borderRadius: const BorderRadius.all(Radius.circular(6))),
          _apiKeyTile(context,
              label: 'Claude API Key',
              iconBg: const Color(0xFFD97706),
              icon: FontAwesomeIcons.wandMagicSparkles,
              value: ai.claudeKey,
              onSave: ai.setClaudeKey,
              borderRadius: const BorderRadius.all(Radius.circular(6))),
          _apiKeyTile(context,
              label: 'DeepSeek API Key',
              iconBg: const Color(0xFF4F46E5),
              icon: FontAwesomeIcons.microchip,
              value: ai.deepSeekKey,
              onSave: ai.setDeepSeekKey,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20))),

          const SizedBox(height: 24),
                  settingsSectionHeader(context,s.models),
          _modelPickerTile(context,
              label: 'Gemini Model',
              iconBg: const Color(0xFF1A73E8),
              icon: FontAwesomeIcons.google,
              selected: ai.geminiModel,
              options: kGeminiModels,
              onSelect: ai.setGeminiModel,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6))),
          _modelPickerTile(context,
              label: 'OpenAI (GPT) Model',
              iconBg: const Color(0xFF10A37F),
              icon: FontAwesomeIcons.robot,
              selected: ai.gptModel,
              options: kGptModels,
              onSelect: ai.setGptModel,
              borderRadius: const BorderRadius.all(Radius.circular(6))),
          _modelPickerTile(context,
              label: 'Claude Model',
              iconBg: const Color(0xFFD97706),
              icon: FontAwesomeIcons.wandMagicSparkles,
              selected: ai.claudeModel,
              options: kClaudeModels,
              onSelect: ai.setClaudeModel,
              borderRadius: const BorderRadius.all(Radius.circular(6))),
          _modelPickerTile(context,
              label: 'DeepSeek Model',
              iconBg: const Color(0xFF4F46E5),
              icon: FontAwesomeIcons.microchip,
              selected: ai.deepSeekModel,
              options: kDeepSeekModels,
              onSelect: ai.setDeepSeekModel,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20))),

          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child:    settingsSectionHeader(context,s.agents)),
              Padding(
                padding: const EdgeInsets.only(right: 4, bottom: 8),
                child: TextButton.icon(
                  onPressed: () => _showAgentDialog(context, null),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(s.newAgent),
                ),
              ),
            ],
          ),
          ...ai.agents.asMap().entries.map((entry) {
            final i = entry.key;
            final agent = entry.value;
            final isFirst = i == 0;
            final isLast = i == ai.agents.length - 1;
            final radius = BorderRadius.vertical(
              top: Radius.circular(isFirst ? 20 : 6),
              bottom: Radius.circular(isLast ? 20 : 6),
            );
            return _agentTile(context, agent, radius);
          }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _apiKeyTile(
    BuildContext context, {
    required String label,
    required Color iconBg,
    required IconData icon,
    required String value,
    required Future<void> Function(String) onSave,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    final card = Theme.of(context).cardTheme;
    final masked = value.isEmpty ? '' : '${value.substring(0, value.length.clamp(0, 8))}••••••••';
    return Card(
    /*   elevation: 0, */
   /*    color: card.color?.withOpacity(0.5), */
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Text(label),
        subtitle: Text(value.isEmpty ? AppStrings.of(context).notConfigured : masked, maxLines: 1),
       //trailing: const Icon(Icons.chevron_right),
        onTap: () => _showApiKeyDialog(context, label: label, current: value, onSave: onSave),
      ),
    );
  }

  Widget _modelPickerTile(
    BuildContext context, {
    required String label,
    required Color iconBg,
    required IconData icon,
    required String selected,
    required List<String> options,
    required Future<void> Function(String) onSelect,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
   // final card = Theme.of(context).cardTheme;
    return Card(
      elevation: 0,
   // color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Text(label),
        subtitle: Text(selected, maxLines: 1),
       // trailing: const Icon(Icons.chevron_right),
        onTap: () => settingsShowPickerDialog(context, label, selected, options, onSelect),
      ),
    );
  }

  void _showApiKeyDialog(
    BuildContext context, {
    required String label,
    required String current,
    required Future<void> Function(String) onSave,
  }) {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController(text: current);
    bool obscure = true;
    showThemedDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: Text(label),
            shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey, width: 0.2), borderRadius: BorderRadiusGeometry.circular(30)),
            content: TextField(
              controller: ctrl,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: s.pasteApiKey,
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
              FilledButton(
                onPressed: () {
                  onSave(ctrl.text.trim());
                  Navigator.pop(ctx);
                },
                child: Text(s.save),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _agentTile(BuildContext context, AiAgent agent, BorderRadiusGeometry borderRadius) {
    final colors = Theme.of(context).colorScheme;
   //  final card = Theme.of(context).cardTheme;
    final avatarColor = Color(agent.colorValue);
    return Card(
      elevation: 0,
   //  color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Text(
            agent.name.isNotEmpty ? agent.name[0].toUpperCase() : 'A',
          //  style:  GoogleFonts.openSans(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Expanded(child: Text(agent.name, maxLines: 1, style: GoogleFonts.openSans(color: colors.onSurface))),
              if (agent.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppStrings.of(context).defaultLabel,
                    maxLines: 1,
                    style: GoogleFonts.openSans(fontSize: 11, color: colors.primary),
                  ),
                ),
            ],
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(agent.focus, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
          /*   IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: AppStrings.of(context).edit,
              onPressed: () => _showAgentDialog(context, agent),
            ), */
            if (!agent.isDefault)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: AppStrings.of(context).delete,
                onPressed: () => _confirmDeleteAgent(context, agent),
              ),
          ],
        ),
        onTap: () => _showAgentDialog(context, agent),
      ),
    );
  }

  void _confirmDeleteAgent(BuildContext context, AiAgent agent) {
    final s = AppStrings.of(context);
    showThemedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteAgent),
        shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey, width: 0.2), borderRadius: BorderRadiusGeometry.circular(30)),
        content: Text(s.deleteAgentConfirm(agent.name)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<AiProvider>().deleteAgent(agent.id);
              Navigator.pop(ctx);
            },
            child: Text(s.delete),
          ),
        ],
      ),
    );
  }

  void _showAgentDialog(BuildContext context, AiAgent? existing) {
    final s = AppStrings.of(context);
    final isNew = existing == null;
    final namectrl = TextEditingController(text: existing?.name ?? '');
    final focusctrl = TextEditingController(text: existing?.focus ?? '');
    final instrctrl = TextEditingController(text: existing?.instructions ?? '');
    Color avatarColor = Color(existing?.colorValue ?? 0xFF607D8B);

    showThemedDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return RepaintBoundary(
            child: Container(
              color: Colors.black.withOpacity(0.45),
              child: AlertDialog(
                title: Text(isNew ? s.newAgentTitle : s.editAgentTitle),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: avatarColor,
                            radius: 22,
                            child: Text(
                              namectrl.text.isNotEmpty ? namectrl.text[0].toUpperCase() : 'A',
                              style:  GoogleFonts.openSans(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _kAgentColors.map((c) {
                                final selected = c.toARGB32() == avatarColor.toARGB32();
                                return GestureDetector(
                                  onTap: () => setState(() => avatarColor = c),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                                      boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)] : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: namectrl,
                        decoration: InputDecoration(labelText: s.agentName, border: const OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: focusctrl,
                        decoration: InputDecoration(labelText: s.agentFocus, border: const OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: instrctrl,
                        decoration: InputDecoration(
                          labelText: s.agentInstructions,
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 6,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
                  FilledButton(
                    onPressed: () {
                      final name = namectrl.text.trim();
                      if (name.isEmpty) return;
                      final aiProv = context.read<AiProvider>();
                      if (isNew) {
                        aiProv.addAgent(AiAgent(
                          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                          name: name,
                          focus: focusctrl.text.trim(),
                          instructions: instrctrl.text.trim(),
                          colorValue: avatarColor.toARGB32(),
                        ));
                      } else {
                        aiProv.updateAgent(existing.copyWith(
                          name: name,
                          focus: focusctrl.text.trim(),
                          instructions: instrctrl.text.trim(),
                          colorValue: avatarColor.toARGB32(),
                        ));
                      }
                      Navigator.pop(ctx);
                    },
                    child: Text(isNew ? s.create : s.save),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  static const _kAgentColors = [
    Color(0xFF1565C0),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFFE65100),
    Color(0xFF00838F),
    Color(0xFF558B2F),
    Color(0xFF4527A0),
    Color(0xFF283593),
    Color(0xFF37474F),
    Color(0xFFF57F17),
    Color(0xFFAD1457),
  ];
}
