import 'dart:ui';

import 'package:build_runner_pkg/build_runner_pkg.dart'
    show BuildPlatform, supportedPlatforms;
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';

import '../app.dart' show showThemedDialog;
import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class RunDebugSettingsPage extends StatelessWidget {
  const RunDebugSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return SettingsPageScaffold(
      title: s.runDebug,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: Consumer<SdkManagerProvider>(
        builder: (context, sdk, _) {
          final installed = sdk.installedSdks;
          return ListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
                      settingsSectionHeader(context,s.environment),
              settingsInfoTile(
                context,
                title: s.rootfsPath,
                subtitle: RuntimeEnvir.usrPath,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(30),
                  bottom: Radius.circular(5),
                ),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folder,
              ),
              settingsInfoTile(
                context,
                title: s.homePath,
                subtitle: RuntimeEnvir.homePath,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                  bottom: Radius.circular(5),
                ),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.house,
              ),
              settingsInfoTile(
                context,
                title: s.projectsPath,
                subtitle: RuntimeEnvir.projectsPath,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(5),
                  bottom: Radius.circular(30),
                ),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folderOpen,
              ),
              const SizedBox(height: 16),
                      settingsSectionHeader(context,s.installedSdks),
              if (installed.isEmpty)
                settingsInfoTile(
                  context,
                  title: s.noSdksInstalled,
                  subtitle: s.installSdksSub,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                    bottom: Radius.circular(30),
                  ),
                  iconBg: Colors.grey,
                  icon: FontAwesomeIcons.boxOpen,
                )
              else
                ...installed.asMap().entries.map((e) {
                  final t = e.value;
                  final isFirst = e.key == 0;
                  final isLast = e.key == installed.length - 1;
                  return settingsInfoTile(
                    context,
                    title: t.displayName,
                    subtitle: sdk.version(t) ?? s.installed,
                    borderRadius: BorderRadius.vertical(
                      top: isFirst ? const Radius.circular(30) : const Radius.circular(5),
                      bottom: isLast ? const Radius.circular(30) : const Radius.circular(5),
                    ),
                    iconBg: Colors.orange,
                    icon: FontAwesomeIcons.wrench,
                  );
                }),
              const SizedBox(height: 16),
                    settingsSectionHeader(context,'Debug Platform'),
              Selector<SettingsProvider, Map<String, String>>(
                selector: (_, s) => s.debugPlatforms,
                builder: (context, debugPlatforms, _) {
                  final debugSdks = installed.where((t) {
                    final platforms = supportedPlatforms(t);
                    return platforms.length > 1 || t == SdkType.flutter;
                  }).toList();

                  if (debugSdks.isEmpty) {
                    return settingsInfoTile(
                      context,
                      title: 'No configurable SDKs',
                      subtitle: 'Install Flutter or another multi-platform SDK',
                      borderRadius: const BorderRadius.all(Radius.circular(30)),
                      iconBg: Colors.grey,
                      icon: FontAwesomeIcons.gear,
                    );
                  }

                  return Column(
                    children: debugSdks.asMap().entries.map((e) {
                      final idx = e.key;
                      final sdkType = e.value;
                      final platforms = supportedPlatforms(sdkType);
                      final savedName = debugPlatforms[sdkType.name];
                      final currentPlatform = savedName != null
                          ? platforms.firstWhere(
                              (p) => p.name == savedName,
                              orElse: () => platforms.first)
                          : platforms.first;
                      final isFirst = idx == 0;
                      final isLast = idx == debugSdks.length - 1;
                      return Card(
                       // elevation: 0,
                      //  color: Theme.of(context).colorScheme.surfaceTint.withValues(alpha: 0.1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: isFirst ? const Radius.circular(30) : const Radius.circular(5),
                            bottom: isLast ? const Radius.circular(30) : const Radius.circular(5),
                          ),
                        ),
                        margin: const EdgeInsets.symmetric(vertical: 1),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Colors.deepPurple,
                            child: Text(sdkType.icon, style:  GoogleFonts.openSans(fontSize: 16)),
                          ),
                          title: Text(sdkType.displayName,
                              style: GoogleFonts.openSans(color: Theme.of(context).colorScheme.onSurface)),
                          subtitle: Text('${currentPlatform.icon}  ${currentPlatform.label}',
                              style: GoogleFonts.openSans(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  fontSize: 12)),
                        //  trailing: const Icon(Icons.chevron_right),
                          onTap: () => _showPlatformPicker(
                            context,
                            sdkType,
                            platforms,
                            currentPlatform,
                            context.read<SettingsProvider>(),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 16),
                      settingsSectionHeader(context,s.lspPaths),
              Selector<SettingsProvider, Map<String, String>>(
                selector: (_, s) => s.lspPaths,
                builder: (context, lspPaths, _) {
                  final lspItems = [
                    ('dart', 'Dart LSP', FontAwesomeIcons.code, Colors.blue),
                    ('ts', 'TypeScript LSP', FontAwesomeIcons.code, Colors.yellow.shade700),
                    ('py', 'Python LSP', FontAwesomeIcons.python, Colors.green),
                    ('kt', 'Kotlin LSP', FontAwesomeIcons.code, Colors.purple),
                  ];
                  return Column(
                    children: lspItems.asMap().entries.map((e) {
                      final idx = e.key;
                      final (ext, label, icon, color) = e.value;
                      final isFirst = idx == 0;
                      final isLast = idx == lspItems.length - 1;
                      return _pathInputTile(
                        context,
                        label: label,
                        iconBg: color,
                        icon: icon,
                        value: lspPaths[ext.toLowerCase()] ?? '',
                        hint: 'e.g. /data/data/com.termux/files/usr/bin/...',
                        onSave: (v) => context.read<SettingsProvider>().setLspPath(ext, v),
                        borderRadius: BorderRadius.vertical(
                          top: isFirst ? const Radius.circular(30) : const Radius.circular(5),
                          bottom: isLast ? const Radius.circular(30) : const Radius.circular(5),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _pathInputTile(
    BuildContext context, {
    required String label,
    required Color iconBg,
    required IconData icon,
    required String value,
    required String hint,
    required Future<void> Function(String) onSave,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
   // final card = Theme.of(context).cardTheme;
    return Card(
      //elevation: 0,
    //  color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(label),
        ),
        subtitle: Text(value.isEmpty ? 'Default (auto-detect)' : value,
            maxLines: 1, overflow: TextOverflow.ellipsis),
       // trailing: const Icon(Icons.chevron_right),
        onTap: () => _showPathInputDialog(context,
            label: label, current: value, hint: hint, onSave: onSave),
      ),
    );
  }

  void _showPlatformPicker(
    BuildContext context,
    SdkType sdkType,
    List<BuildPlatform> platforms,
    BuildPlatform current,
    SettingsProvider settings,
  ) {
    showThemedDialog<void>(
      context: context,
      title: 'Debug platform for ${sdkType.displayName}',
      builder: (ctx) =>  Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in platforms)
              ListTile(
                leading: Text(p.icon),
                title: Text(p.label),
                trailing: p == current
                    ? Icon(Icons.check_rounded,
                        color: Theme.of(ctx).colorScheme.primary, size: 18)
                    : null,
                selected: p == current,
                onTap: () {
                  settings.setDebugPlatform(sdkType.name, p.name);
                  Navigator.pop(ctx);
                },
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.of(context).cancel),
          ),
        ],
      
    );
  }

  void _showPathInputDialog(
    BuildContext context, {
    required String label,
    required String current,
    required String hint,
    required Future<void> Function(String) onSave,
  }) {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController(text: current);
    showThemedDialog<void>(
      context: context,
      title: label,
      builder: (ctx) =>  Padding(
        padding: const EdgeInsets.all(10.0),
        child: TextField(
            controller: ctrl,
            autofocus: true,
            
            decoration: InputDecoration(
              hintText: hint,
              labelText: s.binaryPath,
              border: const OutlineInputBorder(borderSide: BorderSide.none),
            ),
          ),
      ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () {
              onSave(ctrl.text);
              Navigator.pop(context);
            },
            child: Text(s.save),
          ),
        ],
      
    );
  }
}
