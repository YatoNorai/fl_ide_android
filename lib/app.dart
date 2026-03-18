import 'package:app_installer/app_installer.dart';
import 'package:quill_code/quill_code.dart' show EditorTheme;
import 'package:build_runner_pkg/build_runner_pkg.dart';
import 'package:code_editor/code_editor.dart';
import 'package:core/core.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:rootfs_manager/rootfs_manager.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import 'providers/ai_provider.dart';
import 'providers/extensions_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/workspace_screen.dart';

class FlIdeApp extends StatelessWidget {
  const FlIdeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => AiProvider()),
        ChangeNotifierProvider(create: (_) => ExtensionsProvider()),
        ChangeNotifierProvider(create: (_) => RootfsProvider()..checkBootstrap()),
        ChangeNotifierProvider(create: (_) => SdkManagerProvider()..initialize()),
        ChangeNotifierProvider(create: (_) => ProjectManagerProvider()..initialize()),
      ],
      child: Consumer2<SettingsProvider, ExtensionsProvider>(
        builder: (context, settings, extensions, _) {
          final activeEditorTheme = extensions.activeEditorTheme;
          final activeMeta = extensions.activeMeta;

          if (activeEditorTheme != null && activeMeta != null) {
            final extTheme = _buildThemeFromEditorTheme(
                activeEditorTheme, activeMeta.dark);
            return MaterialApp(
              title: 'FL IDE',
              debugShowCheckedModeBanner: false,
              themeMode: activeMeta.dark ? ThemeMode.dark : ThemeMode.light,
              theme: extTheme,
              darkTheme: extTheme,
              builder: _systemBarsBuilder,
              home: const _AppShell(),
            );
          }

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
                builder: _systemBarsBuilder,
                home: const _AppShell(),
              );
            },
          );
        },
      ),
    );
  }

  /// Wraps every route with an AnnotatedRegion so the system navigation bar
  /// and status bar always match the active MaterialTheme.
  static Widget _systemBarsBuilder(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBg = theme.colorScheme.surface;
    final iconBrightness =
        isDark ? Brightness.light : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        // Status bar
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        // Navigation bar — matches the surface colour of the active theme
        systemNavigationBarColor: navBg,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child!,
    );
  }

  /// Builds a full Material ThemeData from an active JSON EditorTheme.
  ThemeData _buildThemeFromEditorTheme(EditorTheme editorTheme, bool isDark) {
    final cs = editorTheme.colorScheme;
    final scheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
      primary: cs.cursor,
      onPrimary: isDark ? Colors.black : Colors.white,
      primaryContainer: cs.cursor.withValues(alpha: 0.2),
      onPrimaryContainer: cs.cursor,
      secondary: cs.keyword,
      onSecondary: isDark ? Colors.black : Colors.white,
      secondaryContainer: cs.keyword.withValues(alpha: 0.2),
      onSecondaryContainer: cs.keyword,
      surface: cs.completionBackground,
      onSurface: cs.textNormal,
      surfaceContainerHighest: cs.lineNumberBackground,
      outline: cs.blockLine,
      outlineVariant: cs.blockLine.withValues(alpha: 0.5),
      error: cs.problemError,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: cs.background,
      appBarTheme: AppBarTheme(
        backgroundColor: cs.lineNumberBackground,
        foregroundColor: cs.textNormal,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: cs.textNormal),
      ),
      cardTheme: CardThemeData(
        color: cs.completionBackground,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.blockLine.withValues(alpha: 0.3)),
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: cs.lineNumberBackground,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cs.cursor,
        unselectedLabelColor: cs.lineNumber,
        indicatorColor: cs.cursor,
        dividerColor: Colors.transparent,
      ),
      dividerColor: cs.blockLine.withValues(alpha: 0.4),
      listTileTheme: ListTileThemeData(
        textColor: cs.textNormal,
        iconColor: cs.lineNumber,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? cs.cursor : cs.lineNumber),
        trackColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected)
                ? cs.cursor.withValues(alpha: 0.4)
                : cs.blockLine),
      ),
      iconTheme: IconThemeData(color: cs.lineNumber),
      textTheme: TextTheme(
        bodySmall: TextStyle(color: cs.lineNumber),
        bodyMedium: TextStyle(color: cs.textNormal),
        bodyLarge: TextStyle(color: cs.textNormal),
        titleSmall: TextStyle(color: cs.textNormal, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: cs.textNormal, fontWeight: FontWeight.w600),
        titleLarge: TextStyle(color: cs.textNormal, fontWeight: FontWeight.w700),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.cursor.withValues(alpha: 0.15),
          foregroundColor: cs.cursor,
          side: BorderSide(color: cs.cursor.withValues(alpha: 0.5)),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cs.completionBackground,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cs.completionBackground,
        titleTextStyle: TextStyle(
            color: cs.textNormal, fontSize: 18, fontWeight: FontWeight.w600),
        contentTextStyle: TextStyle(color: cs.lineNumber),
      ),
      extensions: const [IdeColors.dark],
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
        extensions: const [IdeColors.dark],
      );
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
                  ChangeNotifierProvider<ExtensionsProvider>.value(
                    value: context.read<ExtensionsProvider>(),
                  ),
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
