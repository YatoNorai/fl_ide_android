import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ssh_pkg/ssh_pkg.dart';

import '../providers/ai_provider.dart' show AiProvider;
import '../providers/extensions_provider.dart';
import '../providers/settings_provider.dart';
import 'settings_main_page.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: context.read<SettingsProvider>(),
        ),
        ChangeNotifierProvider<AiProvider>.value(
          value: context.read<AiProvider>(),
        ),
        ChangeNotifierProvider<SshProvider>.value(
          value: context.read<SshProvider>(),
        ),
        ChangeNotifierProvider<ExtensionsProvider>.value(
          value: context.read<ExtensionsProvider>(),
        ),
      ],
      child: const SettingsMainPage(),
    );
  }
}
