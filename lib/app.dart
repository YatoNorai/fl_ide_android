import 'package:app_installer/app_installer.dart';
import 'package:quill_code/quill_code.dart' show EditorTheme, QuillThemeDark, QuillThemeLight;
import 'package:build_runner_pkg/build_runner_pkg.dart';
import 'package:code_editor/code_editor.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:dap_client/dap_client.dart';
import 'package:lsp_client/lsp_client.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:rootfs_manager/rootfs_manager.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';
import 'package:ssh_pkg/ssh_pkg.dart';
import 'package:tofu_expressive/tofu_expressive.dart';
import 'package:expressive_theme_bridge/expressive_theme_bridge.dart';

import 'main.dart' show AppBootData;
import 'providers/ai_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/extensions_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/workspace_screen.dart';

export 'package:core/core.dart' show showThemedDialog;

// ── Global fade page transition ───────────────────────────────────────────────

class _FadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _FadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: child,
    );
  }
}

const _kFadeTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: _FadePageTransitionsBuilder(),
    TargetPlatform.iOS:     _FadePageTransitionsBuilder(),
    TargetPlatform.linux:   _FadePageTransitionsBuilder(),
    TargetPlatform.windows: _FadePageTransitionsBuilder(),
    TargetPlatform.macOS:   _FadePageTransitionsBuilder(),
    TargetPlatform.fuchsia: _FadePageTransitionsBuilder(),
  },
);

// 👇 Defina aqui a cor padrão do app
class FlIdeApp extends StatefulWidget {
  const FlIdeApp({super.key});

  @override
  State<FlIdeApp> createState() => _FlIdeAppState();
}

class _FlIdeAppState extends State<FlIdeApp> {
  late final ExpressiveThemeController _themeController;
  bool? _lastAppliedMaterialYou;

  @override
  void initState() {
    super.initState();
    _themeController = ExpressiveThemeController()..initialize();
  }

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  void _syncMaterialYou(SettingsProvider settings) {
    if (!settings.isLoaded) return;
    if (_lastAppliedMaterialYou == settings.useDynamicColors) return;
    _lastAppliedMaterialYou = settings.useDynamicColors;
    // Apply directly — avoid addPostFrameCallback which delays by one frame
    // and causes a visible color flash when settings load synchronously.
    if (settings.useDynamicColors) {
      _themeController.enableMaterialYou();
    } else {
      _themeController.disableMaterialYou();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ExpressiveThemeScope(
      controller: _themeController,
      child: ExpressiveThemeBuilder(
        controller: _themeController,
        builder: (context, snapshot) {
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsProvider()),
              ChangeNotifierProvider(create: (_) => AiProvider()),
              ChangeNotifierProvider(create: (_) => ChatProvider()),
              ChangeNotifierProvider(create: (_) => ExtensionsProvider()),
              ChangeNotifierProvider(create: (_) => RootfsProvider()..checkBootstrap()),
              ChangeNotifierProvider(create: (_) => SdkManagerProvider()..initialize()),
              ChangeNotifierProvider(create: (_) => ProjectManagerProvider()..initialize()),
              ChangeNotifierProxyProvider<SettingsProvider, SshProvider>(
                create: (_) => SshProvider(),
                update: (ctx, settings, ssh) {
                  ssh!.onSettingsReady(
                    enabled: settings.sshEnabled,
                    host: settings.sshHost,
                    port: settings.sshPort,
                    username: settings.sshUsername,
                    password: settings.sshPassword,
                    keyPath: settings.sshKeyPath,
                    useKey: settings.sshUseKey,
                    remoteProjectsPath: settings.sshProjectsPath,
                  );
                  return ssh;
                },
              ),
            ],
            child: Consumer2<SettingsProvider, ExtensionsProvider>(
              builder: (context, settings, extensions, _) {
                _syncMaterialYou(settings);

                final activeEditorTheme = extensions.activeEditorTheme;
                final activeMeta = extensions.activeMeta;

                const locDelegates = [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ];
                const supportedLocales = [
                  Locale('pt', 'BR'),
                  Locale('pt'),
                  Locale('en'),
                  Locale('es'),
                  Locale('fr'),
                  Locale('de'),
                ];
                final locale = settings.languageLocale;

                late final ThemeData lightTheme;
                late final ThemeData darkTheme;
                late final ThemeMode themeMode;

                if (activeEditorTheme != null && activeMeta != null) {
                  // Tema do editor ativo — usa as cores do editor
                  final brightness = activeMeta.dark ? Brightness.dark : Brightness.light;

                  final editorTheme = _buildEditorThemeData(
                    editorTheme: activeEditorTheme,
                    brightness: brightness,
                    amoled: settings.useAmoled,
                  );

                  lightTheme = editorTheme;
                  darkTheme = editorTheme;
                  themeMode = activeMeta.dark ? ThemeMode.dark : ThemeMode.light;
                } else {
                  // Quando Material You está desativado, o controller cai no
                  // seed roxo padrão do M3 e tinta todas as surfaces.
                  // Neutralizamos só as surfaces, preservando o expressive theme.
                  final applyFix = !settings.useDynamicColors;

                  lightTheme = applyFix
                      ? _neutralizeSurfaces(snapshot.lightTheme, Brightness.light)
                      : snapshot.lightTheme;

                  final baseDark = applyFix
                      ? _neutralizeSurfaces(snapshot.darkTheme, Brightness.dark)
                      : snapshot.darkTheme;

                  darkTheme = settings.useAmoled
                      ? _applyAmoledThemeData(baseDark)
                      : baseDark;

                  themeMode = settings.followSystemTheme
                      ? ThemeMode.system
                      : (settings.useDarkMode ? ThemeMode.dark : ThemeMode.light);
                }

                return MaterialApp(
                  title: 'L A Y E R',
                  debugShowCheckedModeBanner: false,
                  themeMode: themeMode,
                  theme: lightTheme.copyWith(pageTransitionsTheme: _kFadeTransitionsTheme),
                  darkTheme: darkTheme.copyWith(pageTransitionsTheme: _kFadeTransitionsTheme),
                  locale: locale,
                  localizationsDelegates: locDelegates,
                  supportedLocales: supportedLocales,
                  builder: _systemBarsBuilder,
                  home: const _AppShell(),
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// Neutraliza as surfaces roxas que aparecem quando Material You
  /// é desativado e o controller cai no seed padrão do Material 3.
  /// Preserva primary, secondary e todas as extensions do expressive theme.
  static ThemeData _neutralizeSurfaces(ThemeData base, Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final cs = base.colorScheme;

    final neutralScheme = cs.copyWith(
      surface:                 isLight ? const Color(0xFFEEEEEE) : const Color(0xFF1C1C1C),
      surfaceContainer:        isLight ? const Color(0xFFF0F0F0) : const Color(0xFF1F1F1F), // fundo scaffold
      surfaceContainerLow:     isLight ? const Color(0xFFEDEDED) : const Color(0xFF242424),
      surfaceContainerHigh:    isLight ? const Color(0xFFFFFFFF) : const Color(0xFF2C2C2C), // cards — branco puro
      surfaceContainerHighest: isLight ? const Color(0xFFF5F5F5) : const Color(0xFF333333),
      surfaceContainerLowest:  isLight ? const Color(0xFFE0E0E0) : const Color(0xFF161616),
      surfaceDim:              isLight ? const Color(0xFFD9D9D9) : const Color(0xFF111111),
      surfaceBright:           isLight ? const Color(0xFFFFFFFF) : const Color(0xFF2C2C2C),
      surfaceTint:             Colors.transparent,
      // Troca roxo por azul
      primary:                 isLight ? const Color(0xFF1976D2) : const Color(0xFF90CAF9),
      onPrimary:               isLight ? const Color(0xFFFFFFFF) : const Color(0xFF003258),
      primaryContainer:        isLight ? const Color(0xFFD0E4FF) : const Color(0xFF004880),
      onPrimaryContainer:      isLight ? const Color(0xFF001D36) : const Color(0xFFD0E4FF),
      inversePrimary:          isLight ? const Color(0xFF90CAF9) : const Color(0xFF1976D2),
      // Borda e fill do TextField — sem roxo
      outline:                 isLight ? const Color(0xFFCCCCCC) : const Color(0xFF555555),
      outlineVariant:          isLight ? const Color(0xFFE0E0E0) : const Color(0xFF444444),
    );

    return base.copyWith(
      colorScheme: neutralScheme,
      scaffoldBackgroundColor: neutralScheme.surfaceContainer,
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        fillColor: isLight ? const Color(0xFFF5F5F5) : const Color(0xFF2A2A2A),
        border: OutlineInputBorder(
          borderRadius: (base.inputDecorationTheme.border is OutlineInputBorder)
              ? (base.inputDecorationTheme.border as OutlineInputBorder).borderRadius
              : BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFCCCCCC) : const Color(0xFF555555),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: (base.inputDecorationTheme.enabledBorder is OutlineInputBorder)
              ? (base.inputDecorationTheme.enabledBorder as OutlineInputBorder).borderRadius
              : BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFCCCCCC) : const Color(0xFF555555),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: (base.inputDecorationTheme.focusedBorder is OutlineInputBorder)
              ? (base.inputDecorationTheme.focusedBorder as OutlineInputBorder).borderRadius
              : BorderRadius.circular(12),
          borderSide: BorderSide(
            color: neutralScheme.primary,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: (base.inputDecorationTheme.disabledBorder is OutlineInputBorder)
              ? (base.inputDecorationTheme.disabledBorder as OutlineInputBorder).borderRadius
              : BorderRadius.circular(12),
          borderSide: BorderSide(
            color: isLight ? const Color(0xFFDDDDDD) : const Color(0xFF444444),
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: (base.inputDecorationTheme.errorBorder is OutlineInputBorder)
              ? (base.inputDecorationTheme.errorBorder as OutlineInputBorder).borderRadius
              : BorderRadius.circular(12),
          borderSide: BorderSide(color: neutralScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: (base.inputDecorationTheme.focusedErrorBorder is OutlineInputBorder)
              ? (base.inputDecorationTheme.focusedErrorBorder as OutlineInputBorder).borderRadius
              : BorderRadius.circular(12),
          borderSide: BorderSide(color: neutralScheme.error, width: 2),
        ),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: neutralScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: neutralScheme.surfaceContainer,
        foregroundColor: neutralScheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        backgroundColor: neutralScheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: neutralScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: neutralScheme.surfaceContainerHigh,
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static ThemeData _applyAmoledThemeData(ThemeData baseTheme) {
    final cs = baseTheme.colorScheme;
    final effectiveScheme = _applyAmoledScheme(cs);

    const surface = Colors.black;
    const surfaceVariant = Color(0xFF121212);
    const outline = Color(0xFF2A2A2A);

    return baseTheme.copyWith(
      brightness: Brightness.dark,
      colorScheme: effectiveScheme,
      scaffoldBackgroundColor: surface,
      canvasColor: surface,
      appBarTheme: baseTheme.appBarTheme.copyWith(
        backgroundColor: surface,
        foregroundColor: effectiveScheme.onSurface,
        iconTheme: IconThemeData(color: effectiveScheme.onSurface),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: baseTheme.drawerTheme.copyWith(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: baseTheme.dialogTheme.copyWith(
        backgroundColor: surfaceVariant,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: baseTheme.bottomSheetTheme.copyWith(
        backgroundColor: surfaceVariant,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: baseTheme.cardTheme.copyWith(
        color: surfaceVariant,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: baseTheme.navigationBarTheme.copyWith(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
      ),
      tabBarTheme: baseTheme.tabBarTheme.copyWith(
        dividerColor: Colors.transparent,
      ),
      dividerTheme: baseTheme.dividerTheme.copyWith(
        color: outline,
      ),
      iconTheme: baseTheme.iconTheme.copyWith(
        color: effectiveScheme.onSurfaceVariant,
      ),
      listTileTheme: baseTheme.listTileTheme.copyWith(
        textColor: effectiveScheme.onSurface,
        iconColor: effectiveScheme.onSurfaceVariant,
      ),
      switchTheme: baseTheme.switchTheme.copyWith(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? effectiveScheme.primary
              : effectiveScheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? effectiveScheme.primary.withValues(alpha: 0.4)
              : outline,
        ),
      ),
      textTheme: baseTheme.textTheme.apply(
        bodyColor: effectiveScheme.onSurface,
        displayColor: effectiveScheme.onSurface,
      ),
      elevatedButtonTheme: baseTheme.elevatedButtonTheme,
      filledButtonTheme: baseTheme.filledButtonTheme,
      outlinedButtonTheme: baseTheme.outlinedButtonTheme,
      textButtonTheme: baseTheme.textButtonTheme,
      extensions: baseTheme.extensions.values.toList(),
    );
  }

  static ThemeData _buildEditorThemeData({
    required EditorTheme editorTheme,
    required Brightness brightness,
    required bool amoled,
  }) {
    final cs = editorTheme.colorScheme;
    final useAmoled = amoled && brightness == Brightness.dark;

    final background = useAmoled ? Colors.black : cs.background;
    final cardSurface = _tuneCardColor(
      brightness: brightness,
      base: cs.completionBackground,
      amoled: useAmoled,
    );
    final surfaceVariant = useAmoled
        ? const Color(0xFF121212)
        : _adjustTone(
            cs.lineNumberBackground,
            amount: brightness == Brightness.dark ? 0.02 : -0.02,
          );
    final outline = useAmoled ? const Color(0xFF2A2A2A) : cs.blockLine.withValues(alpha: 0.5);

    final seedScheme = ColorScheme.fromSeed(
      seedColor: cs.cursor,
      brightness: brightness,
    );

    final scheme = seedScheme.copyWith(
      primary: cs.cursor,
      onPrimary: _bestOnColor(cs.cursor),
      primaryContainer: cs.cursor.withValues(alpha: 0.18),
      onPrimaryContainer: cs.cursor,
      secondary: cs.keyword,
      onSecondary: _bestOnColor(cs.keyword),
      secondaryContainer: cs.blockLine.withValues(alpha: 0.16),
      onSecondaryContainer: cs.keyword,
      tertiary: cs.lineNumber,
      onTertiary: _bestOnColor(cs.lineNumber),
      tertiaryContainer: cs.lineNumberBackground,
      onTertiaryContainer: cs.lineNumber,
      error: cs.problemError,
      onError: _bestOnColor(cs.problemError),
      errorContainer: cs.problemError.withValues(alpha: 0.16),
      onErrorContainer: cs.problemError,
      surface: background,
      onSurface: cs.textNormal,
      surfaceVariant: surfaceVariant,
      onSurfaceVariant: cs.lineNumber,
      outline: outline,
      outlineVariant: outline,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: cs.textNormal,
      onInverseSurface: background,
      inversePrimary: cs.cursor,
      surfaceTint: Colors.transparent,
    
    );

    final baseTheme = brightness == Brightness.dark
        ? TofuTheme.dark(seedColor: cs.cursor)
        : TofuTheme.light(seedColor: cs.cursor);

    return baseTheme.copyWith(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: cs.textNormal,
        iconTheme: IconThemeData(color: cs.textNormal),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: surfaceVariant,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: cs.textNormal,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: TextStyle(color: cs.lineNumber),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardSurface,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      cardTheme: CardThemeData(
        color: cardSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surfaceVariant,
        surfaceTintColor: Colors.transparent,
        indicatorColor: cs.cursor.withValues(alpha: 0.16),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: cs.cursor,
        unselectedLabelColor: cs.lineNumber,
        indicatorColor: cs.cursor,
        dividerColor: Colors.transparent,
      ),
      dividerColor: outline,
      iconTheme: IconThemeData(color: cs.lineNumber),
      listTileTheme: baseTheme.listTileTheme.copyWith(
        textColor: cs.textNormal,
        iconColor: cs.lineNumber,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? cs.cursor
              : cs.lineNumber,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? cs.cursor.withValues(alpha: 0.4)
              : outline,
        ),
      ),
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
      extensions: brightness == Brightness.dark
          ? const <ThemeExtension<dynamic>>[IdeColors.dark]
          : const <ThemeExtension<dynamic>>[IdeColors.light],
    );
  }

  static Color _tuneCardColor({
    required Color base,
    required Brightness brightness,
    required bool amoled,
  }) {
    final amount = amoled && brightness == Brightness.dark
        ? 0.08
        : brightness == Brightness.dark
            ? 0.06
            : -0.04;
    return _adjustTone(base, amount: amount);
  }

  static Color _adjustTone(Color color, {required double amount}) {
    final hsl = HSLColor.fromColor(color);
    final lightness = (hsl.lightness + amount).clamp(0.0, 1.0);
    return hsl.withLightness(lightness).toColor();
  }

  static ColorScheme _applyAmoledScheme(ColorScheme scheme) {
    return scheme.copyWith(
      surface: Colors.black,
      surfaceVariant: const Color(0xFF121212),
      surfaceTint: Colors.transparent,
      inverseSurface: Colors.white,
      onInverseSurface: Colors.black,
      shadow: Colors.black,
      scrim: Colors.black,
      background: Colors.black,
      onBackground: scheme.onSurface,
    );
  }

  static Color _bestOnColor(Color background) {
    return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  static Widget _systemBarsBuilder(BuildContext context, Widget? child) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final navBg = theme.colorScheme.surface;
    final iconBrightness = isDark ? Brightness.light : Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: navBg,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
      child: child!,
    );
  }
}

// ── Top-level helpers ─────────────────────────────────────────────────────────

/// Builds an [EditorTheme] derived from the current Material [ColorScheme].
/// Used as a fallback when no JSON editor theme is active so the code editor
/// respects the app's palette instead of falling back to a hardcoded dark theme.
EditorTheme editorThemeFromScheme(ColorScheme cs) {
  final isDark = cs.brightness == Brightness.dark;
  final bg     = cs.surface;
  final fgMain = cs.onSurface;
  final fgMuted = cs.onSurfaceVariant;
  final primary   = cs.primary;
  final secondary = cs.secondary;
  final tertiary  = cs.tertiary;
  final error     = cs.error;
  final surfaceHigh     = cs.surfaceContainerHigh;
  final surfaceHighest  = cs.surfaceContainerHighest;

  final base = isDark ? QuillThemeDark.build() : QuillThemeLight.build();

  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      background:                bg,
      lineNumberBackground:      bg,
      currentLineBackground:     surfaceHigh,
      selectionColor:            primary.withValues(alpha: 0.25),
      searchMatchBackground:     tertiary.withValues(alpha: 0.30),
      searchMatchBorder:         tertiary,
      snippetActiveBackground:   primary.withValues(alpha: 0.18),
      snippetInactiveBackground: primary.withValues(alpha: 0.08),
      textNormal:                fgMain,
      lineNumber:                fgMuted.withValues(alpha: 0.7),
      lineNumberCurrent:         fgMain,
      nonPrintableChar:          fgMuted.withValues(alpha: 0.4),
      cursor:                    primary,
      selectionHandle:           primary,
      blockLine:                 fgMuted.withValues(alpha: 0.2),
      blockLineActive:           primary.withValues(alpha: 0.5),
      scrollBarThumb:            fgMuted.withValues(alpha: 0.3),
      scrollBarThumbPressed:     fgMuted.withValues(alpha: 0.6),
      scrollBarTrack:            Colors.transparent,
      completionBackground:      surfaceHighest,
      completionItemBackground:  Colors.transparent,
      completionItemSelected:    primary.withValues(alpha: 0.15),
      completionTextPrimary:     fgMain,
      completionTextSecondary:   fgMuted,
      completionTextMatched:     primary,
      completionBorder:          fgMuted.withValues(alpha: 0.2),
      hoverBackground:           surfaceHighest,
      hoverBorder:               fgMuted.withValues(alpha: 0.2),
      hoverText:                 fgMain,
      signatureBackground:       surfaceHighest,
      signatureBorder:           fgMuted.withValues(alpha: 0.2),
      signatureText:             fgMain,
      signatureHighlightedParam: primary,
      inlayHintForeground:       fgMuted.withValues(alpha: 0.6),
      inlayHintBackground:       surfaceHigh.withValues(alpha: 0.5),
      diagnosticTooltipBackground: surfaceHighest,
      diagnosticTooltipText:     fgMain,
      problemError:              error,
      problemWarning:            secondary,
      problemTypo:               fgMuted,
      bracketPairBorder:         primary.withValues(alpha: 0.5),
      bracketPairFill:           primary.withValues(alpha: 0.08),
      textActionBackground:      surfaceHigh,
      textActionIconColor:       fgMuted,
      ghostTextForeground:       fgMuted.withValues(alpha: 0.5),
    ),
  );
}

// ── App shell ─────────────────────────────────────────────────────────────────

class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  // Gate that holds the splash until:
  //   1. Settings are loaded (always true after warmUp in main — instant)
  //   2. Two frames have been drawn so the ExpressiveTheme + dynamic colors
  //      finish initialising. Without this gate the user sees the system-default
  //      theme flash for one frame before the real palette is applied.
  bool _uiReady = false;

  @override
  void initState() {
    super.initState();
    // addPostFrameCallback fires after the current frame finishes painting.
    // Two nested calls = wait two full frames, enough for the async
    // ExpressiveThemeController.initialize() to complete and rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _uiReady = true);
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SettingsProvider>(
      builder: (context, settings, _) {
        if (!settings.isLoaded || !_uiReady) {
          // Splash: logo centered, no theme-dependent colours so there is
          // nothing to flash even if the theme hasn't settled yet.
          return Scaffold(
            body: Center(
              child: Image.asset(
                'assets/logo.png',
                width: 80,
                height: 80,
                fit: BoxFit.contain,
                color: Theme.of(context).textTheme.bodyLarge?.color,
              ),
            ),
          );
        }

        if (!settings.onboardingDone) return const OnboardingScreen();

        return Consumer<RootfsProvider>(
          builder: (context, rootfs, _) {
            if (rootfs.state == RootfsState.checking) {
              return const Scaffold(body: SizedBox.shrink());
            }
            if (!rootfs.isReady) {
              return DownloadBootstrapScreen(onReady: () {});
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
                      ChangeNotifierProvider(create: (_) => DebugProvider()),
                      ChangeNotifierProvider(
                        create: (_) => AppInstallerProvider(),
                      ),
                      ChangeNotifierProvider<ExtensionsProvider>.value(
                        value: context.read<ExtensionsProvider>(),
                      ),
                    ],
                    child: WorkspaceScreen(
                      project: activeProject,
                      isNewProject: pm.activeProjectIsNew,
                    ),
                  );
                }

                return const HomeScreen();
              },
            );
          },
        );
      },
    );
  }
}