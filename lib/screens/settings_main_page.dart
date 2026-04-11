import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../l10n/app_strings.dart';
import '../widgets/settings_page_widgets.dart';
import 'extensions_screen.dart';
import 'settings_about_page.dart';
import 'settings_ai_page.dart';
import 'settings_editor_page.dart';
import 'settings_file_explorer_page.dart';
import 'settings_general_page.dart';
import 'settings_git_page.dart';
import 'settings_run_debug_page.dart';
import 'settings_terminal_page.dart';
import 'ssh_settings_page.dart';

class SettingsMainPage extends StatelessWidget {
  const SettingsMainPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
        return SettingsPageScaffold(
      title: s.settings,
      canPop: true,
      onBackPressed: () => Navigator.of(context).pop(),
      child: Column(
        children: [SizedBox(height: 30,),
          settingsOptionTile(
            context,
            title: s.general,
            subtitle: s.generalMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const GeneralSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.pink,
            icon: FontAwesomeIcons.gear,
          ),
          settingsOptionTile(
            context,
            title: s.editor,
            subtitle: s.editorMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const EditorSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.blue,
            icon: FontAwesomeIcons.code,
          ),
          settingsOptionTile(
            context,
            title: s.terminal,
            subtitle: s.terminalMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const TerminalSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal,
          ),
          settingsOptionTile(
            context,
            title: s.runDebug,
            subtitle: s.runDebugSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const RunDebugSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.orange,
            icon: FontAwesomeIcons.bug,
          ),
          settingsOptionTile(
            context,
            title: s.extensions,
            subtitle: s.extensionsMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const ExtensionsSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.puzzlePiece,
          ),
          settingsOptionTile(
            context,
            title: s.ai,
            subtitle: s.aiMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const AiSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.robot,
          ),
          settingsOptionTile(
            context,
            title: s.ssh,
            subtitle: s.sshMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const SshSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.server,
          ),
          settingsOptionTile(
            context,
            title: 'Git',
            subtitle: 'Usuário, email e configurações do git',
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const GitSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.deepOrangeAccent,
            icon: FontAwesomeIcons.codeBranch,
          ),
          settingsOptionTile(
            context,
            title: s.about,
            subtitle: s.aboutMenuSub,
            onTap: () => Navigator.of(context).push(settingsFadeRoute(const AboutSettingsPage())),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.amberAccent,
            icon: FontAwesomeIcons.circleInfo,
          ),
          const SizedBox(height: 180),
        ],
      ),
    );
  }
}
