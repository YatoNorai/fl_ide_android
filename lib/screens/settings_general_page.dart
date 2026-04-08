import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../app.dart' show showThemedDialog;
import '../l10n/app_strings.dart';
import '../providers/extensions_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';
import 'extensions_screen.dart';

class GeneralSettingsPage extends StatelessWidget {
  const GeneralSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final vm = context.watch<SettingsProvider>();
    final extProv = context.watch<ExtensionsProvider>();
    final activeMeta = extProv.activeMeta;

    return SettingsPageScaffold(
      title: s.general,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          if (activeMeta != null) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.palette_outlined,
                      color: Theme.of(context).colorScheme.primary, size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.themeActiveBanner(activeMeta.name),
                          style: GoogleFonts.openSans(
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          s.themeActiveBannerSub,
                          style: GoogleFonts.openSans(
                            color: Theme.of(context)
                                .colorScheme
                                .onPrimaryContainer
                                .withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).push(settingsFadeRoute(const ExtensionsSettingsPage())),
                    child: Text(s.extensions),
                  ),
                ],
              ),
            ),
          ],
                  settingsSectionHeader(context,s.secLangRegion),
          Stack(
            children: [
              _languageTile(context, vm),
              Positioned(
                top: 4,
                right: 4,
                child: settingsInfoButton(context, s.language, s.languageInfo),
              ),
            ],
          ),
          const SizedBox(height: 20),
                  settingsSectionHeader(context,s.secThemeAppearance),
          settingsSwitchTile(
            context,
            title: s.followSystemTheme,
            subtitle: vm.followSystemTheme ? s.followSystemOn : s.followSystemOff,
            value: vm.followSystemTheme,
            onChanged: vm.setFollowSystemTheme,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.circleHalfStroke,
            enabled: activeMeta == null,
            infoText: s.followSystemThemeInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.darkMode,
            subtitle: vm.useDarkMode ? s.darkModeOn : s.darkModeOff,
            value: vm.useDarkMode,
            onChanged: vm.setUseDarkMode,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.moon,
            enabled: activeMeta == null,
            infoText: s.darkModeInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.amoledBlack,
            subtitle: s.amoledBlackSub,
            value: vm.useAmoled,
            onChanged: vm.setUseAmoled,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.mobileScreen,
            enabled: activeMeta == null,
            infoText: s.amoledBlackInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.dynamicColors,
            subtitle: s.dynamicColorsSub,
            value: vm.useDynamicColors,
            onChanged: vm.setUseDynamicColors,
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.palette,
            enabled: activeMeta == null,
            infoText: s.dynamicColorsInfo,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
          ),
  /*         settingsSwitchTile(
            context,
            title: s.liquidGlass,
            subtitle: s.liquidGlassSub,
            value: vm.liquidGlass,
            onChanged: vm.setLiquidGlass,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.droplet,
            infoText: s.liquidGlassInfo,
          ), */
          const SizedBox(height: 250),
        ],
      ),
    );
  }

  Widget _languageTile(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
  //  final card = Theme.of(context).cardTheme;
    final current = kSupportedLanguages.firstWhere(
      (l) => l.code == vm.language,
      orElse: () => kSupportedLanguages.first,
    );
    return Card(
   //   elevation: 0,
    //   color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.deepPurple,
          child: Icon(Icons.language_rounded, color: Colors.white, size: 20),
        ),
        title: Text(s.language, style: GoogleFonts.openSans(color: colors.onSurface, fontSize: 14)),
        subtitle: Text(current.native),
 
        onTap: () => _showLanguagePicker(context, vm),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    showThemedDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.language),
        shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey, width: 0.2), borderRadius: BorderRadiusGeometry.circular(30)),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final lang in kSupportedLanguages)
              ListTile(
                title: Text(lang.native),
                subtitle: Text(
                  lang.name,
                  style: GoogleFonts.openSans(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                trailing: lang.code == vm.language
                    ? Icon(Icons.check_rounded, color: Theme.of(ctx).colorScheme.primary)
                    : null,
                selected: lang.code == vm.language,
                onTap: () {
                  vm.setLanguage(lang.code);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
      ),
    );
  }
}
