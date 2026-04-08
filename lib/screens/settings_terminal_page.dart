import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class TerminalSettingsPage extends StatelessWidget {
  const TerminalSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return SettingsPageScaffold(
      title: s.terminal,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
                  settingsSectionHeader(context,s.terminal),
          settingsOptionTile(
            context,
            title: s.terminalFontSize,
            subtitle: s.colorSchemeSub,
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(10),
            ),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal,
          ),
          settingsOptionTile(
            context,
            title: s.colorScheme,
            subtitle: s.colorSchemeSub,
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(10),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.green,
            icon: FontAwesomeIcons.paintRoller,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
