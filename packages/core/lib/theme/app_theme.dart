import 'package:flutter/material.dart';

/// AndroidIDE-identical dark theme
class AppTheme {
  AppTheme._();

  // ── Core palette (matches AndroidIDE screenshots exactly) ──────────────────
  static const Color darkBg          = Color(0xFF1C1C1E); // near-black bg
  static const Color darkSurface     = Color(0xFF2C2C2E); // surface/sheet
  static const Color darkSideRail    = Color(0xFF111113); // icon rail
  static const Color darkPanel       = Color(0xFF242426); // panels
  static const Color darkSidebar     = Color(0xFF1E1E20); // file tree
  static const Color darkTabBar      = Color(0xFF1C1C1E);
  static const Color darkTabActive   = Color(0xFF1C1C1E);
  static const Color darkTabInactive = Color(0xFF111113);
  static const Color darkBorder      = Color(0xFF3A3A3C);
  static const Color darkDivider     = Color(0xFF2C2C2E);

  // Accent — blue like AndroidIDE
  static const Color darkAccent      = Color(0xFF7B9EFF);
  static const Color darkAccentDeep  = Color(0xFF3D5280);

  // Text
  static const Color darkText        = Color(0xFFFFFFFF);
  static const Color darkTextMuted   = Color(0xFF8E8E93); // system gray
  static const Color darkTextDim     = Color(0xFF636366); // system gray 2

  // Semantic
  static const Color darkSuccess     = Color(0xFF30D158); // system green
  static const Color darkError       = Color(0xFFFF453A); // system red
  static const Color darkWarning     = Color(0xFFFFD60A); // system yellow
  static const Color darkInfo        = Color(0xFF64D2FF); // system teal

  // Editor-specific
  static const Color darkSelection   = Color(0xFF1E3A5F);
  static const Color darkInputBg     = Color(0xFF2C2C2E);
  static const Color darkTreeHover   = Color(0xFF2C2C2E);
  static const Color darkTreeSelected = Color(0xFF3A3A3C);
  static const Color darkStatusBar   = Color(0xFF111113);
  static const Color darkTitleBar    = Color(0xFF1C1C1E);
  static const Color darkScrollThumb = Color(0xFF48484A);
  static const Color darkCardBg      = Color(0xFF2C2C2E);
  static const Color darkCardBorder  = Color(0xFF3A3A3C);

  // Light (minimal)
  static const Color lightBg         = Color(0xFFF2F2F7);
  static const Color lightSidebar    = Color(0xFFFFFFFF);
  static const Color lightTabBar     = Color(0xFFF2F2F7);
  static const Color lightBorder     = Color(0xFFD1D1D6);
  static const Color lightAccent     = Color(0xFF007AFF);
  static const Color lightText       = Color(0xFF000000);

  // ── ThemeData ──────────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBg,
        colorScheme: const ColorScheme.dark(
          brightness: Brightness.dark,
          primary: darkAccent,
          onPrimary: Color(0xFF001849),
          primaryContainer: darkAccentDeep,
          onPrimaryContainer: Color(0xFFDAE2FF),
          secondary: darkSuccess,
          onSecondary: Color(0xFF003300),
          tertiary: darkInfo,
          onTertiary: Color(0xFF002A3A),
          error: darkError,
          onError: Color(0xFF300000),
          surface: darkSurface,
          onSurface: darkText,
          surfaceContainerHighest: darkBorder,
          outline: darkBorder,
          outlineVariant: darkDivider,
          shadow: Colors.black,
          inverseSurface: Color(0xFFF2F2F7),
          onInverseSurface: Color(0xFF1C1C1E),
          inversePrimary: Color(0xFF4361EE),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: darkTitleBar,
          foregroundColor: darkText,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: darkText, fontSize: 20, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: darkText, size: 24),
          actionsIconTheme: IconThemeData(color: darkText, size: 24),
        ),
        drawerTheme: const DrawerThemeData(
          backgroundColor: darkSurface,
          elevation: 0,
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: darkTitleBar,
          elevation: 0,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: darkAccent,
          unselectedLabelColor: darkTextMuted,
          indicatorColor: darkAccent,
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12),
          dividerColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: darkCardBg,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: false,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: darkBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: darkBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: darkAccent, width: 2),
          ),
          labelStyle: const TextStyle(color: darkTextMuted),
          hintStyle: const TextStyle(color: darkTextDim),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: darkAccent,
            foregroundColor: const Color(0xFF001849),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: darkAccent,
            side: const BorderSide(color: darkBorder),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: darkAccent,
            shape: const StadiumBorder(),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: darkDivider,
          thickness: 0.5,
          space: 0.5,
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: darkSurface,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        listTileTheme: const ListTileThemeData(
          textColor: darkText,
          iconColor: darkText,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(darkScrollThumb),
          thickness: WidgetStateProperty.all(3),
          radius: const Radius.circular(4),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? Colors.white
                  : darkTextMuted),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? darkAccent
                  : darkBorder),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: darkSurface,
          contentTextStyle: TextStyle(color: darkText),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
          behavior: SnackBarBehavior.floating,
        ),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
              color: darkText, fontSize: 20, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(
              color: darkText, fontSize: 16, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(
              color: darkText, fontSize: 14, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: darkText, fontSize: 16),
          bodyMedium: TextStyle(color: darkText, fontSize: 14),
          bodySmall: TextStyle(color: darkTextMuted, fontSize: 12),
          labelLarge: TextStyle(
              color: darkText, fontSize: 14, fontWeight: FontWeight.w500),
          labelMedium: TextStyle(color: darkTextMuted, fontSize: 12),
          labelSmall: TextStyle(color: darkTextDim, fontSize: 11),
        ),
        iconTheme: const IconThemeData(color: darkText, size: 24),
        extensions: const [IdeColors.dark],
      );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: lightBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: lightAccent,
          brightness: Brightness.light,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF2F2F7),
          foregroundColor: Color(0xFF000000),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
              color: Color(0xFF000000), fontSize: 20, fontWeight: FontWeight.w700),
          iconTheme: IconThemeData(color: Color(0xFF000000), size: 24),
          actionsIconTheme: IconThemeData(color: Color(0xFF000000), size: 24),
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Color(0xFF007AFF),
          unselectedLabelColor: Color(0xFF6E6E73),
          indicatorColor: Color(0xFF007AFF),
          labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          unselectedLabelStyle: TextStyle(fontSize: 12),
          dividerColor: Colors.transparent,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFD1D1D6),
          thickness: 0.5,
          space: 0.5,
        ),
        listTileTheme: const ListTileThemeData(
          textColor: Color(0xFF000000),
          iconColor: Color(0xFF000000),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        ),
        popupMenuTheme: const PopupMenuThemeData(
          color: Color(0xFFFFFFFF),
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          backgroundColor: Color(0xFFFFFFFF),
          contentTextStyle: TextStyle(color: Color(0xFF000000)),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12))),
          behavior: SnackBarBehavior.floating,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: false,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D1D6)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF007AFF), width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF6E6E73)),
          hintStyle: const TextStyle(color: Color(0xFF6E6E73)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF000000), size: 24),
        textTheme: const TextTheme(
          titleLarge: TextStyle(
              color: Color(0xFF000000), fontSize: 20, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(
              color: Color(0xFF000000), fontSize: 16, fontWeight: FontWeight.w600),
          titleSmall: TextStyle(
              color: Color(0xFF000000), fontSize: 14, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(color: Color(0xFF000000), fontSize: 16),
          bodyMedium: TextStyle(color: Color(0xFF000000), fontSize: 14),
          bodySmall: TextStyle(color: Color(0xFF6E6E73), fontSize: 12),
          labelLarge: TextStyle(
              color: Color(0xFF000000), fontSize: 14, fontWeight: FontWeight.w500),
          labelMedium: TextStyle(color: Color(0xFF6E6E73), fontSize: 12),
          labelSmall: TextStyle(color: Color(0xFF6E6E73), fontSize: 11),
        ),
        extensions: const [IdeColors.light],
      );
}

/// IDE-specific color tokens
class IdeColors extends ThemeExtension<IdeColors> {
  final Color sidebar;
  final Color tabBar;
  final Color border;
  final Color treeHover;
  final Color treeSelected;
  final Color statusBar;
  final Color textMuted;
  final Color selection;
  final Color success;
  final Color warning;
  final Color info;

  const IdeColors({
    required this.sidebar,
    required this.tabBar,
    required this.border,
    required this.treeHover,
    required this.treeSelected,
    required this.statusBar,
    required this.textMuted,
    required this.selection,
    required this.success,
    required this.warning,
    required this.info,
  });

  static const IdeColors dark = IdeColors(
    sidebar: AppTheme.darkSidebar,
    tabBar: AppTheme.darkTabBar,
    border: AppTheme.darkBorder,
    treeHover: AppTheme.darkTreeHover,
    treeSelected: AppTheme.darkTreeSelected,
    statusBar: AppTheme.darkStatusBar,
    textMuted: AppTheme.darkTextMuted,
    selection: AppTheme.darkSelection,
    success: AppTheme.darkSuccess,
    warning: AppTheme.darkWarning,
    info: AppTheme.darkInfo,
  );

  static const IdeColors light = IdeColors(
    sidebar: AppTheme.lightSidebar,
    tabBar: AppTheme.lightTabBar,
    border: AppTheme.lightBorder,
    treeHover: Color(0xFFE8EAED),
    treeSelected: Color(0xFFCCDDFF),
    statusBar: AppTheme.lightAccent,
    textMuted: Color(0xFF8E8E93),
    selection: Color(0xFFADD6FF),
    success: Color(0xFF34C759),
    warning: Color(0xFFFF9F0A),
    info: Color(0xFF32ADE6),
  );

  @override
  IdeColors copyWith({
    Color? sidebar, Color? tabBar, Color? border,
    Color? treeHover, Color? treeSelected, Color? statusBar,
    Color? textMuted, Color? selection,
    Color? success, Color? warning, Color? info,
  }) => IdeColors(
    sidebar: sidebar ?? this.sidebar,
    tabBar: tabBar ?? this.tabBar,
    border: border ?? this.border,
    treeHover: treeHover ?? this.treeHover,
    treeSelected: treeSelected ?? this.treeSelected,
    statusBar: statusBar ?? this.statusBar,
    textMuted: textMuted ?? this.textMuted,
    selection: selection ?? this.selection,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    info: info ?? this.info,
  );

  @override
  IdeColors lerp(IdeColors? other, double t) => this;
}
