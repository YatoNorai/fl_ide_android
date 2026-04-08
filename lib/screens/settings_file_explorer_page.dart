import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class FileExplorerSettingsPage extends StatelessWidget {
  const FileExplorerSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return SettingsPageScaffold(
      title: s.extensions, // overwritten by router label? kept only as fallback
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
                  settingsSectionHeader(context,s.showHiddenFiles),
          settingsOptionTile(
            context,
            title: s.showHiddenFiles,
            subtitle: s.showHiddenFilesSub,
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.indigoAccent,
            icon: FontAwesomeIcons.file,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
