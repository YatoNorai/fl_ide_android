import 'package:app_installer/app_installer.dart';
import 'package:build_runner_pkg/build_runner_pkg.dart';
import 'package:code_editor/code_editor.dart';
import 'package:core/core.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:rootfs_manager/rootfs_manager.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/workspace_screen.dart';

class FlIdeApp extends StatelessWidget {
  const FlIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => RootfsProvider()..checkBootstrap()),
        ChangeNotifierProvider(create: (_) => SdkManagerProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ProjectManagerProvider()..initialize()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          return DynamicColorBuilder(
            builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
              final lightScheme = settings.useDynamicColors && lightDynamic != null
                  ? lightDynamic.harmonized()
                  : ColorScheme.fromSeed(
                      seedColor: Colors.blue,
                      brightness: Brightness.light,
                    );
              final darkScheme = settings.useDynamicColors && darkDynamic != null
                  ? darkDynamic.harmonized()
                  : ColorScheme.fromSeed(
                      seedColor: Colors.blueGrey,
                      brightness: Brightness.dark,
                    );

              final themeMode = settings.followSystemTheme
                  ? ThemeMode.system
                  : (settings.useDarkMode ? ThemeMode.dark : ThemeMode.light);

              return MaterialApp(
                title: 'FL IDE',
                debugShowCheckedModeBanner: false,
                themeMode: themeMode,
                theme: _buildLightTheme(lightScheme),
                darkTheme: _buildDarkTheme(darkScheme, amoled: settings.useAmoled),
                home: const _SplashGate(),
              );
            },
          );
        },
      ),
    );
  }

  ThemeData _buildLightTheme(ColorScheme scheme) => ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      );

  ThemeData _buildDarkTheme(ColorScheme scheme, {bool amoled = false}) =>
      ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: amoled ? Colors.black : null,
        appBarTheme: AppBarTheme(
          backgroundColor: amoled ? Colors.black : scheme.surface,
          foregroundColor: scheme.onSurface,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        // Preserve IDE-specific static colors as extensions
        extensions: const [IdeColors.dark],
      );
}

// ── Splash gate ───────────────────────────────────────────────────────────────

class _SplashGate extends StatefulWidget {
  const _SplashGate();

  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  bool _splashDone = false;

  @override
  Widget build(BuildContext context) {
    if (!_splashDone) {
      return SplashScreen(
        onFinished: () => setState(() => _splashDone = true),
      );
    }
    return const _AppShell();
  }
}

// ── App shell ─────────────────────────────────────────────────────────────────

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return Consumer<RootfsProvider>(
      builder: (context, rootfs, _) {
        if (!rootfs.isReady) {
          return DownloadBootstrapScreen(
            onReady: () {},
          );
        }

        return Consumer<ProjectManagerProvider>(
          builder: (context, pm, _) {
            final activeProject = pm.activeProject;

            if (activeProject != null) {
              return MultiProvider(
                providers: [
                  ChangeNotifierProvider(create: (_) => EditorProvider()),
                  ChangeNotifierProvider(create: (_) => TerminalProvider()),
                  ChangeNotifierProvider(create: (_) => BuildProvider()),
                  ChangeNotifierProvider(create: (_) => LspProvider()),
                  ChangeNotifierProvider(create: (_) => AppInstallerProvider()),
                ],
                child: WorkspaceScreen(project: activeProject),
              );
            }

            return const HomeScreen();
          },
        );
      },
    );
  }
}
