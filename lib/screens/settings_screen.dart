import 'dart:ui';

import 'package:build_runner_pkg/build_runner_pkg.dart'
    show BuildPlatform, supportedPlatforms;
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';

import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_strings.dart';
import '../models/ai_agent.dart';
import '../providers/ai_provider.dart' show AiProvider, kGeminiModels, kGptModels, kClaudeModels, kDeepSeekModels;
import '../providers/extensions_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/animated_toggle.dart';
import 'extensions_screen.dart';

// ── Settings screen ───────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Reuse the root providers so changes reflect immediately in app.dart
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(
          value: context.read<SettingsProvider>(),
        ),
        ChangeNotifierProvider<AiProvider>.value(
          value: context.read<AiProvider>(),
        ),
      ],
      child: const _SettingsScreenBody(),
    );
  }
}

class _SettingsScreenBody extends StatefulWidget {
  const _SettingsScreenBody();

  @override
  State<_SettingsScreenBody> createState() => _SettingsScreenBodyState();
}

class _SettingsScreenBodyState extends State<_SettingsScreenBody> {
  final _scrollCtrl = ScrollController();
  SettingsPage? _prevPage;

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(0,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const double maxExtent = 140.0;
    const double minExtent = kToolbarHeight;
    const double expandedLeft = 20.0;
    const double collapsedLeft = 60.0;
    const double expandedBottom = 0.0;
    const double collapsedBottom = 8.0;

    return Consumer<SettingsProvider>(
      builder: (context, vm, _) {
        final s = AppStrings.of(context);
        // Scroll to top whenever the page changes.
        if (_prevPage != vm.currentPage) {
          _prevPage = vm.currentPage;
          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
        }

        return PopScope(
          canPop: vm.currentPage == SettingsPage.main,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) vm.goBack();
          },
          child: Scaffold(
            backgroundColor: colors.surface,
            body: CustomScrollView(
              controller: _scrollCtrl,
              slivers: [
                SliverAppBar(
                  expandedHeight: maxExtent,
                  floating: false,
                  pinned: true,
                  backgroundColor: colors.surface,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: colors.onSurface),
                    onPressed: () {
                      if (vm.currentPage == SettingsPage.main) {
                        Navigator.of(context).pop();
                      } else {
                        vm.goBack();
                      }
                    },
                  ),
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final double currentHeight = constraints.biggest.height;
                      double t = (currentHeight - minExtent) /
                          (maxExtent - minExtent);
                      t = t.clamp(0.0, 1.0);
                      final double left = expandedLeft +
                          (collapsedLeft - expandedLeft) * (1 - t);
                      final double bottom = expandedBottom +
                          (collapsedBottom - expandedBottom) * (1 - t);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                              decoration:
                                  BoxDecoration(color: colors.surface)),
                          Positioned(
                            left: left,
                            bottom: bottom,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 16, bottom: 8),
                              child: Text(
                                s.settings,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // ── Animated page content ─────────────────────────────────
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeIn,
                      switchOutCurve: Curves.easeOut,
                      transitionBuilder: (child, animation) =>
                          FadeTransition(opacity: animation, child: child),
                      child: KeyedSubtree(
                        key: ValueKey(vm.currentPage),
                        child: vm.currentPage == SettingsPage.main
                            ? _buildMain(context, vm)
                            : _buildPage(context, vm),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMain(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    return Column(
      children: [
        _buildOption(context,
            title: s.general,
            subtitle: s.generalMenuSub,
            onTap: () => vm.navigateToPage(SettingsPage.general),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.pink,
            icon: FontAwesomeIcons.gear),
        _buildOption(context,
            title: s.editor,
            subtitle: s.editorMenuSub,
            onTap: () => vm.navigateToPage(SettingsPage.editor),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blue,
            icon: FontAwesomeIcons.code),
        _buildOption(context,
            title: s.terminal,
            subtitle: s.terminalMenuSub,
            onTap: () => vm.navigateToPage(SettingsPage.terminal),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal),
        _buildOption(context,
            title: s.runDebug,
            subtitle: s.runDebugSub,
            onTap: () => vm.navigateToPage(SettingsPage.runDebug),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.orange,
            icon: FontAwesomeIcons.bug),
        _buildOption(context,
            title: s.extensions,
            subtitle: s.extensionsMenuSub,
            onTap: () => vm.navigateToPage(SettingsPage.extensions),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.puzzlePiece),
        _buildOption(context,
            title: s.ai,
            subtitle: s.aiMenuSub,
            onTap: () => vm.navigateToPage(SettingsPage.ai),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.robot),
        _buildOption(context,
            title: s.about,
            subtitle: s.aboutMenuSub,
            onTap: () => vm.navigateToPage(SettingsPage.about),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.amberAccent,
            icon: FontAwesomeIcons.circleInfo),
        const SizedBox(height: 150),
      ],
    );
  }

  Widget _buildPage(BuildContext context, SettingsProvider vm) {
    final Key pageKey = ValueKey(vm.currentPage.toString());
    switch (vm.currentPage) {
      case SettingsPage.main:
        return const SizedBox.shrink();
      case SettingsPage.general:
        return Container(key: pageKey, child: _buildGeneral(context, vm));
      case SettingsPage.editor:
        return Container(key: pageKey, child: _buildEditor(context, vm));
      case SettingsPage.fileExplorer:
        return Container(key: pageKey, child: _buildFileExplorer(context));
      case SettingsPage.terminal:
        return Container(key: pageKey, child: _buildTerminal(context));
      case SettingsPage.runDebug:
        return Container(key: pageKey, child: _buildRunDebug(context));
      case SettingsPage.extensions:
        return Container(key: pageKey, child: const ExtensionsPageContent());
      case SettingsPage.ai:
        return Container(key: pageKey, child: _buildAi(context));
      case SettingsPage.about:
        return Container(key: pageKey, child: _buildAbout(context));
    }
  }

  // ── General settings ──────────────────────────────────────────────────────
  Widget _buildGeneral(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    final extProv = context.watch<ExtensionsProvider>();
    final activeMeta = extProv.activeMeta;

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        if (activeMeta != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4)),
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
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        s.themeActiveBannerSub,
                        style: TextStyle(
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
                  onPressed: () =>
                      context.read<SettingsProvider>().navigateToPage(
                            SettingsPage.extensions,
                          ),
                  child: Text(s.extensions),
                ),
              ],
            ),
          ),
        ],
        _sectionHeader(s.secLangRegion),
        _languageTile(context, vm),
        const SizedBox(height: 20),
        _sectionHeader(s.secThemeAppearance),
        _switchTile(context,
            title: s.followSystemTheme,
            subtitle: vm.followSystemTheme
                ? s.followSystemOn
                : s.followSystemOff,
            value: vm.followSystemTheme,
            onChanged: vm.setFollowSystemTheme,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.circleHalfStroke,
            enabled: activeMeta == null),
        _switchTile(context,
            title: s.darkMode,
            subtitle: vm.useDarkMode ? s.darkModeOn : s.darkModeOff,
            value: vm.useDarkMode,
            onChanged: vm.setUseDarkMode,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.moon,
            enabled: activeMeta == null),
        _switchTile(context,
            title: s.amoledBlack,
            subtitle: s.amoledBlackSub,
            value: vm.useAmoled,
            onChanged: vm.setUseAmoled,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.mobileScreen,
            enabled: activeMeta == null),
        _switchTile(context,
            title: s.dynamicColors,
            subtitle: s.dynamicColorsSub,
            value: vm.useDynamicColors,
            onChanged: vm.setUseDynamicColors,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.palette,
            enabled: activeMeta == null),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Language tile ─────────────────────────────────────────────────────────
  Widget _languageTile(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final current = kSupportedLanguages.firstWhere(
      (l) => l.code == vm.language,
      orElse: () => kSupportedLanguages.first,
    );
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.deepPurple,
          child: Icon(Icons.language_rounded, color: Colors.white, size: 20),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(s.language,
              style: TextStyle(color: colors.onSurface, fontSize: 14)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(current.native,
              style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showLanguagePicker(context, vm),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => RepaintBoundary(
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                child: AlertDialog(
            title: Text(s.language),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final lang in kSupportedLanguages)
                  ListTile(
                    title: Text(lang.native),
                    subtitle: Text(
                      lang.name,
                      style: TextStyle(
                        color:
                            Theme.of(ctx).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    trailing: lang.code == vm.language
                        ? Icon(Icons.check_rounded,
                            color: Theme.of(ctx).colorScheme.primary)
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
        ),
      ),
    );
  }

  // ── Editor settings ───────────────────────────────────────────────────────
  Widget _buildEditor(BuildContext context, SettingsProvider vm) {
    final s = AppStrings.of(context);
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // ── Font & Display ────────────────────────────────────────────────
        _sectionHeader(s.secFontDisplay),
        _fontPickerTile(context, vm),
        _sliderTile(context,
            title: s.fontSize,
            value: vm.fontSize,
            min: 8,
            max: 32,
            valueLabel: '${vm.fontSize.round()}px',
            onChanged: (v) => vm.setFontSize(v.roundToDouble()),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blue,
            icon: FontAwesomeIcons.font,
            divisions: 17),
        _switchTile(context,
            title: s.lineNumbers,
            subtitle: s.lineNumbersSub,
            value: vm.showLineNumbers,
            onChanged: vm.setShowLineNumbers,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.listOl),
        _switchTile(context,
            title: s.fixedGutter,
            subtitle: s.fixedGutterSub,
            value: vm.fixedGutter,
            onChanged: vm.setFixedGutter,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.tableColumns),
        _switchTile(context,
            title: s.minimap,
            subtitle: s.minimapSub,
            value: vm.showMinimap,
            onChanged: vm.setShowMinimap,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.map),
        _switchTile(context,
            title: s.symbolBar,
            subtitle: s.symbolBarSub,
            value: vm.showSymbolBar,
            onChanged: vm.setShowSymbolBar,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.keyboard),

        // ── Behavior ──────────────────────────────────────────────────────
        _sectionHeader(s.secBehavior),
        _switchTile(context,
            title: s.wordWrap,
            subtitle: s.wordWrapSub,
            value: vm.wordWrap,
            onChanged: vm.setWordWrap,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.alignJustify),
        _switchTile(context,
            title: s.autoIndent,
            subtitle: s.autoIndentSub,
            value: vm.autoIndent,
            onChanged: vm.setAutoIndent,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.green,
            icon: FontAwesomeIcons.indent),
        _switchTile(context,
            title: s.autoClosePairs,
            subtitle: s.autoClosePairsSub,
            value: vm.symbolPairAutoClose,
            onChanged: vm.setSymbolPairAutoClose,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.orange,
            icon: FontAwesomeIcons.braille),
        _switchTile(context,
            title: s.autoCompletion,
            subtitle: s.autoCompletionSub,
            value: vm.autoCompletion,
            onChanged: vm.setAutoCompletion,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.amber,
            icon: FontAwesomeIcons.wandMagicSparkles),
        _switchTile(context,
            title: s.formatOnSave,
            subtitle: s.formatOnSaveSub,
            value: vm.formatOnSave,
            onChanged: vm.setFormatOnSave,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.wandMagic),
        _switchTile(context,
            title: s.stickyScroll,
            subtitle: s.stickyScrollSub,
            value: vm.stickyScroll,
            onChanged: vm.setStickyScroll,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.brown,
            icon: FontAwesomeIcons.thumbtack),

        // ── Indentation ───────────────────────────────────────────────────
        _sectionHeader(s.secIndentation),
        _pickerTile(context,
            title: s.tabSize,
            subtitle: s.tabSizeSub,
            value: vm.tabSize.toString(),
            options: const ['2', '4', '8'],
            onChanged: (v) => vm.setTabSize(int.parse(v)),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.alignLeft),
        _switchTile(context,
            title: s.useSpaces,
            subtitle: s.useSpacesSub,
            value: vm.useSpaces,
            onChanged: vm.setUseSpaces,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.rulerHorizontal),

        // ── Cursor ────────────────────────────────────────────────────────
        _sectionHeader(s.secCursor),
        _sliderTile(context,
            title: s.cursorBlinkSpeed,
            value: vm.cursorBlinkMs.toDouble(),
            min: 200,
            max: 1000,
            valueLabel: '${vm.cursorBlinkMs}ms',
            onChanged: (v) => vm.setCursorBlinkMs(v.round()),
            borderRadius: const BorderRadius.all(Radius.circular(30)),
            iconBg: Colors.deepOrange,
            icon: FontAwesomeIcons.iCursor,
            divisions: 8),

        // ── Code Structure ────────────────────────────────────────────────
        _sectionHeader(s.secCodeStructure),
        _switchTile(context,
            title: s.lightbulbActions,
            subtitle: s.lightbulbActionsSub,
            value: vm.showLightbulb,
            onChanged: vm.setShowLightbulb,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.yellow.shade700,
            icon: FontAwesomeIcons.lightbulb),
        _switchTile(context,
            title: s.foldArrows,
            subtitle: s.foldArrowsSub,
            value: vm.showFoldArrows,
            onChanged: vm.setShowFoldArrows,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.angleDown),
        _switchTile(context,
            title: s.blockLines,
            subtitle: s.blockLinesSub,
            value: vm.showBlockLines,
            onChanged: vm.setShowBlockLines,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.gripLinesVertical),
        _switchTile(context,
            title: s.indentDots,
            subtitle: s.indentDotsSub,
            value: vm.showIndentDots,
            onChanged: vm.setShowIndentDots,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.ellipsis),

        // ── Highlight ─────────────────────────────────────────────────────
        _sectionHeader(s.secHighlight),
        _switchTile(context,
            title: s.highlightCurrentLine,
            subtitle: s.highlightCurrentLineSub,
            value: vm.highlightCurrentLine,
            onChanged: vm.setHighlightCurrentLine,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.highlighter),
        _switchTile(context,
            title: s.highlightActiveBlock,
            subtitle: s.highlightActiveBlockSub,
            value: vm.highlightActiveBlock,
            onChanged: vm.setHighlightActiveBlock,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.borderAll),
        _pickerTile(context,
            title: s.highlightStyle,
            subtitle: s.highlightStyleSub,
            value: vm.lineHighlightStyle,
            options: const ['fill', 'stroke', 'accentBar', 'none'],
            onChanged: vm.setLineHighlightStyle,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.fillDrip),

        // ── Advanced ──────────────────────────────────────────────────────
        _sectionHeader(s.secAdvanced),
        _switchTile(context,
            title: s.diagnosticIndicators,
            subtitle: s.diagnosticIndicatorsSub,
            value: vm.showDiagnosticIndicators,
            onChanged: vm.setShowDiagnosticIndicators,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.red,
            icon: FontAwesomeIcons.triangleExclamation),
        _switchTile(context,
            title: s.readOnly,
            subtitle: s.readOnlySub,
            value: vm.readOnly,
            onChanged: vm.setReadOnly,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.grey,
            icon: FontAwesomeIcons.lock),

        const SizedBox(height: 32),
      ],
    );
  }

  // ── Font picker tile ──────────────────────────────────────────────────────

  Widget _fontPickerTile(BuildContext context, SettingsProvider vm) {
    const fonts = [
      ('monospace', 'Default (Monospace)'),
      ('FiraCode', 'Fira Code'),
      ('CourierPrime', 'Courier Prime'),
      ('SpaceMono', 'Space Mono'),
      ('RobotoMono', 'Roboto Mono'),
      ('OpenSans', 'Open Sans'),
    ];
    final currentLabel = fonts.firstWhere(
      (f) => f.$1 == vm.fontFamily,
      orElse: () => ('monospace', 'Default (Monospace)'),
    ).$2;
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(10)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.deepOrange,
          child: FaIcon(FontAwesomeIcons.font, size: 16, color: Colors.white),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(AppStrings.of(context).fontFamily, style: TextStyle(color: colors.onSurface, fontSize: 14)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(currentLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          showDialog<void>(
            context: context,
            builder: (ctx) {
              return RepaintBoundary(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                      child: AlertDialog(
                    title: Text(AppStrings.of(context).fontFamily),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: fonts.map((f) {
                        return RadioListTile<String>(
                          value: f.$1,
                          groupValue: vm.fontFamily,
                          title: Text(
                            f.$2,
                            style: TextStyle(fontFamily: f.$1 == 'monospace' ? null : f.$1),
                          ),
                          subtitle: Text(
                            'The quick brown fox',
                            style: TextStyle(
                              fontFamily: f.$1 == 'monospace' ? null : f.$1,
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                          onChanged: (v) {
                            if (v != null) {
                              vm.setFontFamily(v);
                              Navigator.pop(ctx);
                            }
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Picker tile (replaces dropdown) ───────────────────────────────────────

  Widget _pickerTile(
    BuildContext context, {
    required String title,
    String? subtitle,
    required String value,
    required List<String> options,
    required ValueChanged<String> onChanged,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(title, style: TextStyle(color: colors.onSurface, fontSize: 14)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(value, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showPickerDialog(context, title, value, options, onChanged),
      ),
    );
  }

  void _showPickerDialog(
    BuildContext context,
    String title,
    String current,
    List<String> options,
    ValueChanged<String> onChanged,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return RepaintBoundary(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                      child: AlertDialog(
              title: Text(title),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: options.map((o) {
                  return RadioListTile<String>(
                    value: o,
                    groupValue: current,
                    title: Text(o),
                    onChanged: (v) {
                      if (v != null) {
                        onChanged(v);
                        Navigator.pop(ctx);
                      }
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Slider tile ───────────────────────────────────────────────────────────

  Widget _sliderTile(
    BuildContext context, {
    required String title,
    required double value,
    required double min,
    required double max,
    required String valueLabel,
    required ValueChanged<double> onChanged,
    required Color iconBg,
    required IconData icon,
    int? divisions,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
                backgroundColor: iconBg,
                child: FaIcon(icon, size: 16, color: Colors.white)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title,
                            style: TextStyle(fontSize: 14, color: colors.onSurface)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(valueLabel,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                                fontFamily: 'monospace')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Material 3 / Android-style thick slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      year2023: false,
                    ),
                    child: Slider(
                      year2023: false,
                      value: value.clamp(min, max),
                      min: min,
                      max: max,
                      onChanged: onChanged,
                      divisions: divisions,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── File explorer settings ────────────────────────────────────────────────
  Widget _buildFileExplorer(BuildContext context) {
    final s = AppStrings.of(context);
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader(s.showHiddenFiles),
        _buildOption(context,
            title: s.showHiddenFiles,
            subtitle: s.showHiddenFilesSub,
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(30)),
            iconBg: Colors.indigoAccent,
            icon: FontAwesomeIcons.file),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Terminal settings ─────────────────────────────────────────────────────
  Widget _buildTerminal(BuildContext context) {
    final s = AppStrings.of(context);
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader(s.terminal),
        _buildOption(context,
            title: s.terminalFontSize,
            subtitle: s.colorSchemeSub,
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal),
        _buildOption(context,
            title: s.colorScheme,
            subtitle: s.colorSchemeSub,
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.green,
            icon: FontAwesomeIcons.paintRoller),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Run & Debug settings ──────────────────────────────────────────────────
  Widget _buildRunDebug(BuildContext context) {
    return Consumer<SdkManagerProvider>(
      builder: (context, sdk, _) {
        final s = AppStrings.of(context);
        final installed = sdk.installedSdks;
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _sectionHeader(s.environment),
            _infoTile(context,
                title: s.rootfsPath,
                subtitle: RuntimeEnvir.usrPath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folder),
            _infoTile(context,
                title: s.homePath,
                subtitle: RuntimeEnvir.homePath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.house),
            _infoTile(context,
                title: s.projectsPath,
                subtitle: RuntimeEnvir.projectsPath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folderOpen),
            const SizedBox(height: 16),
            _sectionHeader(s.installedSdks),
            if (installed.isEmpty)
              _infoTile(context,
                  title: s.noSdksInstalled,
                  subtitle: s.installSdksSub,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30), bottom: Radius.circular(30)),
                  iconBg: Colors.grey,
                  icon: FontAwesomeIcons.boxOpen)
            else
              ...installed.asMap().entries.map((e) {
                final t = e.value;
                final isFirst = e.key == 0;
                final isLast = e.key == installed.length - 1;
                return _infoTile(context,
                    title: t.displayName,
                    subtitle: sdk.version(t) ?? s.installed,
                    borderRadius: BorderRadius.vertical(
                      top: isFirst ? const Radius.circular(30) : const Radius.circular(10),
                      bottom: isLast ? const Radius.circular(30) : const Radius.circular(10),
                    ),
                    iconBg: Colors.orange,
                    icon: FontAwesomeIcons.wrench);
              }),
            const SizedBox(height: 16),
            _sectionHeader('Debug Platform'),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
                // Only show SDKs that are installed AND support multiple platforms
                // or need explicit platform selection (Flutter)
                final debugSdks = installed.where((t) {
                  final platforms = supportedPlatforms(t);
                  return platforms.length > 1 || t == SdkType.flutter;
                }).toList();

                if (debugSdks.isEmpty) {
                  return _infoTile(context,
                      title: 'No configurable SDKs',
                      subtitle: 'Install Flutter or another multi-platform SDK',
                      borderRadius: const BorderRadius.all(Radius.circular(30)),
                      iconBg: Colors.grey,
                      icon: FontAwesomeIcons.gear);
                }

                return Column(
                  children: debugSdks.asMap().entries.map((e) {
                    final idx = e.key;
                    final sdkType = e.value;
                    final platforms = supportedPlatforms(sdkType);
                    final savedName = settings.debugPlatformFor(sdkType.name);
                    final currentPlatform = savedName != null
                        ? platforms.firstWhere(
                            (p) => p.name == savedName,
                            orElse: () => platforms.first)
                        : platforms.first;
                    final isFirst = idx == 0;
                    final isLast = idx == debugSdks.length - 1;
                    return Card(
                      elevation: 0,
                      color: Theme.of(context).colorScheme.surfaceTint.withValues(alpha: 0.1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: isFirst ? const Radius.circular(30) : const Radius.circular(10),
                          bottom: isLast ? const Radius.circular(30) : const Radius.circular(10),
                        ),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.deepPurple,
                          child: Text(sdkType.icon,
                              style: const TextStyle(fontSize: 16)),
                        ),
                        title: Text(sdkType.displayName,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface)),
                        subtitle: Text(
                            '${currentPlatform.icon}  ${currentPlatform.label}',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 12)),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showPlatformPicker(
                            context, sdkType, platforms, currentPlatform, settings),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 16),
            _sectionHeader(s.lspPaths),
            Consumer<SettingsProvider>(
              builder: (context, settings, _) {
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
                    return _pathInputTile(context,
                        label: label,
                        iconBg: color,
                        icon: icon,
                        value: settings.lspPathFor(ext),
                        hint: 'e.g. /data/data/com.termux/files/usr/bin/...',
                        onSave: (v) => settings.setLspPath(ext, v),
                        borderRadius: BorderRadius.vertical(
                          top: isFirst
                              ? const Radius.circular(30)
                              : const Radius.circular(10),
                          bottom: isLast
                              ? const Radius.circular(30)
                              : const Radius.circular(10),
                        ));
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  void _showPlatformPicker(
    BuildContext context,
    SdkType sdkType,
    List<BuildPlatform> platforms,
    BuildPlatform current,
    SettingsProvider settings,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Debug platform for ${sdkType.displayName}'),
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in platforms)
              ListTile(
                leading: Text(p.icon, style: const TextStyle(fontSize: 20)),
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
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppStrings.of(ctx).cancel),
          ),
        ],
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
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(
            backgroundColor: iconBg,
            child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(label, style: TextStyle(color: colors.onSurface)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            value.isEmpty ? 'Default (auto-detect)' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showPathInputDialog(context,
            label: label, current: value, hint: hint, onSave: onSave),
      ),
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
    showDialog<void>(
      context: context,
      builder: (ctx) => RepaintBoundary(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                      child: AlertDialog(
            title: Text(label),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: hint,
                labelText: s.binaryPath,
                border: const OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.cancel),
              ),
              TextButton(
                onPressed: () {
                  onSave(ctrl.text);
                  Navigator.pop(ctx);
                },
                child: Text(s.save),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── AI settings ───────────────────────────────────────────────────────────
  Widget _buildAi(BuildContext context) {
    final s = AppStrings.of(context);
    final ai = context.watch<AiProvider>();

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // ── API Keys ──────────────────────────────────────────────────────
        _sectionHeader(s.apiKeys),
        _apiKeyTile(context,
            label: 'Gemini API Key',
            iconBg: const Color(0xFF1A73E8),
            icon: FontAwesomeIcons.google,
            value: ai.geminiKey,
            onSave: ai.setGeminiKey,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6))),
        _apiKeyTile(context,
            label: 'OpenAI (GPT) API Key',
            iconBg: const Color(0xFF10A37F),
            icon: FontAwesomeIcons.robot,
            value: ai.gptKey,
            onSave: ai.setGptKey,
            borderRadius: const BorderRadius.all(Radius.circular(6))),
        _apiKeyTile(context,
            label: 'Claude API Key',
            iconBg: const Color(0xFFD97706),
            icon: FontAwesomeIcons.wandMagicSparkles,
            value: ai.claudeKey,
            onSave: ai.setClaudeKey,
            borderRadius: const BorderRadius.all(Radius.circular(6))),
        _apiKeyTile(context,
            label: 'DeepSeek API Key',
            iconBg: const Color(0xFF4F46E5),
            icon: FontAwesomeIcons.microchip,
            value: ai.deepSeekKey,
            onSave: ai.setDeepSeekKey,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20))),

        const SizedBox(height: 24),

        // ── Models ────────────────────────────────────────────────────────
        _sectionHeader(s.models),
        _modelPickerTile(context,
            label: 'Gemini Model',
            iconBg: const Color(0xFF1A73E8),
            icon: FontAwesomeIcons.google,
            selected: ai.geminiModel,
            options: kGeminiModels,
            onSelect: ai.setGeminiModel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6))),
        _modelPickerTile(context,
            label: 'OpenAI (GPT) Model',
            iconBg: const Color(0xFF10A37F),
            icon: FontAwesomeIcons.robot,
            selected: ai.gptModel,
            options: kGptModels,
            onSelect: ai.setGptModel,
            borderRadius: const BorderRadius.all(Radius.circular(6))),
        _modelPickerTile(context,
            label: 'Claude Model',
            iconBg: const Color(0xFFD97706),
            icon: FontAwesomeIcons.wandMagicSparkles,
            selected: ai.claudeModel,
            options: kClaudeModels,
            onSelect: ai.setClaudeModel,
            borderRadius: const BorderRadius.all(Radius.circular(6))),
        _modelPickerTile(context,
            label: 'DeepSeek Model',
            iconBg: const Color(0xFF4F46E5),
            icon: FontAwesomeIcons.microchip,
            selected: ai.deepSeekModel,
            options: kDeepSeekModels,
            onSelect: ai.setDeepSeekModel,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20))),

        const SizedBox(height: 24),

        // ── Agents ────────────────────────────────────────────────────────
        Row(
          children: [
            Expanded(child: _sectionHeader(s.agents)),
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 8),
              child: TextButton.icon(
                onPressed: () => _showAgentDialog(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.newAgent),
              ),
            ),
          ],
        ),
        ...ai.agents.asMap().entries.map((entry) {
          final i = entry.key;
          final agent = entry.value;
          final isFirst = i == 0;
          final isLast = i == ai.agents.length - 1;
          final radius = BorderRadius.vertical(
            top: Radius.circular(isFirst ? 20 : 6),
            bottom: Radius.circular(isLast ? 20 : 6),
          );
          return _agentTile(context, agent, radius);
        }),

        const SizedBox(height: 32),
      ],
    );
  }


  Widget _apiKeyTile(
    BuildContext context, {
    required String label,
    required Color iconBg,
    required IconData icon,
    required String value,
    required Future<void> Function(String) onSave,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    final masked = value.isEmpty ? '' : '${value.substring(0, value.length.clamp(0, 8))}••••••••';
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(label, style: TextStyle(color: colors.onSurface)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(value.isEmpty ? AppStrings.of(context).notConfigured : masked, maxLines: 1),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showApiKeyDialog(context, label: label, current: value, onSave: onSave),
      ),
    );
  }

  Widget _modelPickerTile(
    BuildContext context, {
    required String label,
    required Color iconBg,
    required IconData icon,
    required String selected,
    required List<String> options,
    required Future<void> Function(String) onSelect,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(label, style: TextStyle(color: colors.onSurface)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(selected, maxLines: 1),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _showPickerDialog(context, label, selected, options, onSelect),
      ),
    );
  }

  void _showApiKeyDialog(
    BuildContext context, {
    required String label,
    required String current,
    required Future<void> Function(String) onSave,
  }) {
    final s = AppStrings.of(context);
    final ctrl = TextEditingController(text: current);
    bool obscure = true;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return RepaintBoundary(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                      child: AlertDialog(
                title: Text(label),
                content: TextField(
                  controller: ctrl,
                  obscureText: obscure,
                  decoration: InputDecoration(
                    hintText: s.pasteApiKey,
                    suffixIcon: IconButton(
                      icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                      onPressed: () => setState(() => obscure = !obscure),
                    ),
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
                  FilledButton(
                    onPressed: () {
                      onSave(ctrl.text.trim());
                      Navigator.pop(ctx);
                    },
                    child: Text(s.save),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _agentTile(BuildContext context, AiAgent agent, BorderRadiusGeometry borderRadius) {
    final colors = Theme.of(context).colorScheme;
    final avatarColor = Color(agent.colorValue);
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: avatarColor,
          child: Text(
            agent.name.isNotEmpty ? agent.name[0].toUpperCase() : 'A',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(child: Text(agent.name, style: TextStyle(color: colors.onSurface))),
              if (agent.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    AppStrings.of(context).defaultLabel,
                    style: TextStyle(fontSize: 11, color: colors.primary),
                  ),
                ),
            ],
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(agent.focus, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: AppStrings.of(context).edit,
              onPressed: () => _showAgentDialog(context, agent),
            ),
            if (!agent.isDefault)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: AppStrings.of(context).delete,
                onPressed: () => _confirmDeleteAgent(context, agent),
              ),
          ],
        ),
        onTap: () => _showAgentDialog(context, agent),
      ),
    );
  }

  void _confirmDeleteAgent(BuildContext context, AiAgent agent) {
    final s = AppStrings.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => RepaintBoundary(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                      child: AlertDialog(
            title: Text(s.deleteAgent),
            content: Text(s.deleteAgentConfirm(agent.name)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () {
                  context.read<AiProvider>().deleteAgent(agent.id);
                  Navigator.pop(ctx);
                },
                child: Text(s.delete),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAgentDialog(BuildContext context, AiAgent? existing) {
    final s = AppStrings.of(context);
    final isNew = existing == null;
    final namectrl  = TextEditingController(text: existing?.name ?? '');
    final focusctrl = TextEditingController(text: existing?.focus ?? '');
    final instrctrl = TextEditingController(text: existing?.instructions ?? '');
    Color avatarColor = Color(existing?.colorValue ?? 0xFF607D8B);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return RepaintBoundary(
                  child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 10),
                      child: AlertDialog(
                title: Text(isNew ? s.newAgentTitle : s.editAgentTitle),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar color picker row
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: avatarColor,
                            radius: 22,
                            child: Text(
                              namectrl.text.isNotEmpty ? namectrl.text[0].toUpperCase() : 'A',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: _kAgentColors.map((c) {
                                final selected = c.toARGB32() == avatarColor.toARGB32();
                                return GestureDetector(
                                  onTap: () => setState(() => avatarColor = c),
                                  child: Container(
                                    width: 26,
                                    height: 26,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: selected ? Border.all(color: Colors.white, width: 2.5) : null,
                                      boxShadow: selected ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)] : null,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: namectrl,
                        decoration: InputDecoration(labelText: s.agentName, border: const OutlineInputBorder()),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: focusctrl,
                        decoration: InputDecoration(labelText: s.agentFocus, border: const OutlineInputBorder()),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: instrctrl,
                        decoration: InputDecoration(
                          labelText: s.agentInstructions,
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                        ),
                        maxLines: 6,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
                  FilledButton(
                    onPressed: () {
                      final name = namectrl.text.trim();
                      if (name.isEmpty) return;
                      final aiProv = context.read<AiProvider>();
                      if (isNew) {
                        aiProv.addAgent(AiAgent(
                          id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                          name: name,
                          focus: focusctrl.text.trim(),
                          instructions: instrctrl.text.trim(),
                          colorValue: avatarColor.toARGB32(),
                        ));
                      } else {
                        aiProv.updateAgent(existing.copyWith(
                          name: name,
                          focus: focusctrl.text.trim(),
                          instructions: instrctrl.text.trim(),
                          colorValue: avatarColor.toARGB32(),
                        ));
                      }
                      Navigator.pop(ctx);
                    },
                    child: Text(isNew ? s.create : s.save),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  static const _kAgentColors = [
    Color(0xFF1565C0), // blue
    Color(0xFF2E7D32), // green
    Color(0xFF6A1B9A), // purple
    Color(0xFFC62828), // red
    Color(0xFFE65100), // deep orange
    Color(0xFF00838F), // cyan
    Color(0xFF558B2F), // light green
    Color(0xFF4527A0), // deep purple
    Color(0xFF283593), // indigo
    Color(0xFF37474F), // blue grey
    Color(0xFFF57F17), // amber
    Color(0xFFAD1457), // pink
  ];

  // ── About settings ────────────────────────────────────────────────────────
  Widget _buildAbout(BuildContext context) {
    final s = AppStrings.of(context);
    final colors = Theme.of(context).colorScheme;

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // ── Hero ──────────────────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.only(bottom: 24),
          padding: const EdgeInsets.symmetric(vertical: 32),
          decoration: BoxDecoration(
            color: colors.surfaceTint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/logo.png', width: 80, height: 80, fit: BoxFit.contain, color: Theme.of(context).textTheme.bodyLarge?.color,),
              ),
              const SizedBox(height: 16),
              const Text(
                'FL IDE',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
             
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.mobileDevEnv,
                style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.6)),
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
                  'v1.0.0',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Developer ─────────────────────────────────────────────────────
        _sectionHeader(s.developer),
        _aboutCard(context,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFF1565C0),
              child: FaIcon(FontAwesomeIcons.code, size: 16, color: Colors.white),
            ),
            title: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(s.developer),
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Yato'),
            ),
          ),
        ),
        _aboutCard(context,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(20)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.black87,
              child: const FaIcon(FontAwesomeIcons.github, size: 16, color: Colors.white),
            ),
            title: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('GitHub', ),
            ),
            subtitle: const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('github.com/YatoNorai'),
            ),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => launchUrl(
              Uri.parse('https://github.com/YatoNorai'),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),

        const SizedBox(height: 20),

        // ── SDKs suportados ───────────────────────────────────────────────
        _sectionHeader(s.supportedSdks),
        _aboutCard(context,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              _sdkRow(context, icon: FontAwesomeIcons.java,   color: const Color(0xFFE65100), label: 'Java',       detail: 'JDK 17 / 21'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.java,   color: const Color(0xFF00695C), label: 'Kotlin',     detail: 'Kotlin 2.x'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.python, color: const Color(0xFF1565C0), label: 'Python',     detail: '3.x'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.nodeJs, color: const Color(0xFF2E7D32), label: 'Node.js',    detail: 'LTS'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.rust,   color: const Color(0xFFBF360C), label: 'Rust',       detail: 'stable toolchain'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.cuttlefish, color: const Color(0xFF37474F), label: 'C / C++', detail: 'clang + NDK'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.flutter, color: const Color(0xFF0277BD), label: 'Flutter / Dart', detail: 'stable channel'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.gem,    color: const Color(0xFF880E4F), label: 'Ruby',       detail: '3.x'),
              _sdkDivider(context),
              _sdkRow(context, icon: FontAwesomeIcons.php,    color: const Color(0xFF4527A0), label: 'PHP',        detail: '8.x'),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Licença ───────────────────────────────────────────────────────
        _sectionHeader(s.licenseLabel),
        _aboutCard(context,
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
                  const Text(
                    'MIT License',
                    style: TextStyle( fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: const Text('Open Source', style: TextStyle(fontSize: 11, color: Colors.green)),
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
                style: TextStyle(
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
    );
  }

  Widget _aboutCard(
    BuildContext context, {
    required Widget child,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
    EdgeInsetsGeometry? padding,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfaceTint.withValues(alpha: 0.1),
        borderRadius: borderRadius,
      ),
      child: child,
    );
  }

  Widget _sdkRow(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required String detail,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: color.withValues(alpha: 0.15),
            child: FaIcon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: const TextStyle( fontWeight: FontWeight.w500)),
          ),
          Text(detail, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
        ],
      ),
    );
  }

  Widget _sdkDivider(BuildContext context) => Divider(
        height: 1,
        thickness: 0.5,
        color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
      );

  // ── Helper builders ───────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(title),
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(subtitle, maxLines: 1),
              )
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(title, style: TextStyle(color: colors.onSurface)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(subtitle, maxLines: 2),
        ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
    bool enabled = true,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Card(
        elevation: 0,
        color: colors.surfaceTint.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: borderRadius),
        margin: const EdgeInsets.symmetric(vertical: 2),
        child: AbsorbPointer(
          absorbing: !enabled,
          child: ListTile(
            minTileHeight: 50,
            leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
            title: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(title, ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(subtitle),
            ),
            trailing: SizedBox(
              width: 55,
              height: 34,
              child: AnimatedToggle(value: value, onChanged: onChanged),
            ),
            onTap: () => onChanged(!value),
          ),
        ),
      ),
    );
  }
}
