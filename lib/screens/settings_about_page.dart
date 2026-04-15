import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    //final card = Theme.of(context).cardTheme;
    return SettingsPageScaffold(
      title: s.about,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 24),
            
            shape: RoundedRectangleBorder(
             // color: card.color?.withOpacity(0.5),
              borderRadius: BorderRadius.circular(24),
              side:BorderSide( color: colors.outline.withValues(alpha: 0.15)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'assets/logo.png',
                      width: 80,
                      height: 80,
                      fit: BoxFit.contain,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 16),
                   Text(
                    'L A Y E R',
                    style: GoogleFonts.montserrat(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.mobileDevEnv,
                    style: GoogleFonts.openSans(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colors.primary.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'v0.0.2',
                      style: GoogleFonts.openSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          settingsSectionHeader(context,s.developer),
          settingsAboutCard(
            context,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6)),
            child: const ListTile(
              leading: CircleAvatar(
                backgroundColor: Color(0xFF1565C0),
                child: FaIcon(FontAwesomeIcons.code, size: 16, color: Colors.white),
              ),
              title: Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('Developer'),
              ),
              subtitle: Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Yato'),
              ),
            ),
          ),
          settingsAboutCard(
            context,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.black87,
                child: FaIcon(FontAwesomeIcons.github, size: 16, color: Colors.white),
              ),
              title: const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text('GitHub'),
              ),
              subtitle: const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('github.com'),
              ),
              trailing: const Icon(Icons.open_in_new, size: 18),
              onTap: () => launchUrl(
                Uri.parse('https://google.com'),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ),

          const SizedBox(height: 20),
                  settingsSectionHeader(context,s.supportedSdks),
          settingsAboutCard(
            context,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              children: [
                settingsSdkRow(context, icon: FontAwesomeIcons.java, color: const Color(0xFFE65100), label: 'Java', detail: 'JDK 17 / 21'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.java, color: const Color(0xFF00695C), label: 'Kotlin', detail: 'Kotlin 2.x'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.python, color: const Color(0xFF1565C0), label: 'Python', detail: '3.x'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.nodeJs, color: const Color(0xFF2E7D32), label: 'Node.js', detail: 'LTS'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.rust, color: const Color(0xFFBF360C), label: 'Rust', detail: 'stable toolchain'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.cuttlefish, color: const Color(0xFF37474F), label: 'C / C++', detail: 'clang + NDK'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.flutter, color: const Color(0xFF0277BD), label: 'Flutter / Dart', detail: 'stable channel'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.gem, color: const Color(0xFF880E4F), label: 'Ruby', detail: '3.x'),
                settingsSdkDivider(context),
                settingsSdkRow(context, icon: FontAwesomeIcons.php, color: const Color(0xFF4527A0), label: 'PHP', detail: '8.x'),
              ],
            ),
          ),

          const SizedBox(height: 20),
               settingsSectionHeader(context,s.licenseLabel),
          settingsAboutCard(
            context,
            padding: const EdgeInsets.all(20),
            borderRadius: BorderRadius.circular(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.green.shade700,
                      child: const FaIcon(FontAwesomeIcons.scaleBalanced, size: 14, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                     Text(
                      'MIT License',
                      style: GoogleFonts.openSans(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                      ),
                      child:  Text('Open Source', style: GoogleFonts.openSans(fontSize: 11, color: Colors.green)),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Copyright © 2025 Yato\n\n'
                  'Permission is hereby granted, free of charge, to any person obtaining a copy '
                  'of this software and associated documentation files (the "Software"), to deal '
                  'in the Software without restriction, including without limitation the rights '
                  'to use, copy, modify, merge, publish, distribute, sublicense, and/or sell '
                  'copies of the Software.',
                  style: GoogleFonts.openSans(
                    fontSize: 12,
                    height: 1.6,
                    color: colors.onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
