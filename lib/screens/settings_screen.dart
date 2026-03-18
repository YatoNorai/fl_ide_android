import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';

import 'package:url_launcher/url_launcher.dart';

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
                            child: const Padding(
                              padding: EdgeInsets.only(top: 16, bottom: 8),
                              child: Text(
                                'Settings',
                                style: TextStyle(
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
    return Column(
      children: [
        _buildOption(context,
            title: 'General',
            subtitle: 'Appearance and behavior settings.',
            onTap: () => vm.navigateToPage(SettingsPage.general),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.pink,
            icon: FontAwesomeIcons.gear),
        _buildOption(context,
            title: 'Editor',
            subtitle: 'Code editor preferences.',
            onTap: () => vm.navigateToPage(SettingsPage.editor),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blue,
            icon: FontAwesomeIcons.code),
        _buildOption(context,
            title: 'Terminal',
            subtitle: 'Built-in terminal settings.',
            onTap: () => vm.navigateToPage(SettingsPage.terminal),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal),
        _buildOption(context,
            title: 'Run & Debug',
            subtitle: 'SDKs and build options.',
            onTap: () => vm.navigateToPage(SettingsPage.runDebug),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.orange,
            icon: FontAwesomeIcons.bug),
        _buildOption(context,
            title: 'Extensions',
            subtitle: 'Themes and add-ons.',
            onTap: () => vm.navigateToPage(SettingsPage.extensions),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.puzzlePiece),
        _buildOption(context,
            title: 'AI',
            subtitle: 'API keys and agent configurations.',
            onTap: () => vm.navigateToPage(SettingsPage.ai),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.robot),
        _buildOption(context,
            title: 'About',
            subtitle: 'App information.',
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
                        'Tema "${activeMeta.name}" ativo',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'As configurações de aparência estão desativadas. '
                        'Desative o tema nas Extensões para usar as configurações padrão.',
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
                  child: const Text('Extensões'),
                ),
              ],
            ),
          ),
        ],
        _sectionHeader('Theme & Appearance'),
        _switchTile(context,
            title: 'Follow System Theme',
            subtitle: vm.followSystemTheme
                ? 'App follows system theme'
                : 'Manual theme control',
            value: vm.followSystemTheme,
            onChanged: vm.setFollowSystemTheme,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.circleHalfStroke,
            enabled: activeMeta == null),
        _switchTile(context,
            title: 'Dark Mode',
            subtitle: vm.useDarkMode ? 'Dark theme active' : 'Light theme active',
            value: vm.useDarkMode,
            onChanged: vm.setUseDarkMode,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.moon,
            enabled: activeMeta == null),
        _switchTile(context,
            title: 'AMOLED Black',
            subtitle: 'Pure black background for OLED screens',
            value: vm.useAmoled,
            onChanged: vm.setUseAmoled,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.mobileScreen,
            enabled: activeMeta == null),
        _switchTile(context,
            title: 'Dynamic Colors',
            subtitle: 'Use Material You colors from wallpaper',
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

  // ── Editor settings ───────────────────────────────────────────────────────
  Widget _buildEditor(BuildContext context, SettingsProvider vm) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // ── Font & Display ────────────────────────────────────────────────
        _sectionHeader('Font & Display'),
        _fontPickerTile(context, vm),
        _sliderTile(context,
            title: 'Font Size',
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
            title: 'Line Numbers',
            subtitle: 'Show line numbers in the gutter',
            value: vm.showLineNumbers,
            onChanged: vm.setShowLineNumbers,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.listOl),
        _switchTile(context,
            title: 'Fixed Gutter',
            subtitle: 'Line numbers stay fixed while scrolling',
            value: vm.fixedGutter,
            onChanged: vm.setFixedGutter,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.tableColumns),
        _switchTile(context,
            title: 'Minimap',
            subtitle: 'Code preview panel on the right',
            value: vm.showMinimap,
            onChanged: vm.setShowMinimap,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.map),
        _switchTile(context,
            title: 'Symbol Bar',
            subtitle: 'Mobile keyboard helpers  { } ; = …',
            value: vm.showSymbolBar,
            onChanged: vm.setShowSymbolBar,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.keyboard),

        // ── Behavior ──────────────────────────────────────────────────────
        _sectionHeader('Behavior'),
        _switchTile(context,
            title: 'Word Wrap',
            subtitle: 'Wrap long lines to the editor width',
            value: vm.wordWrap,
            onChanged: vm.setWordWrap,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.alignJustify),
        _switchTile(context,
            title: 'Auto-Indent',
            subtitle: 'Maintain indentation automatically',
            value: vm.autoIndent,
            onChanged: vm.setAutoIndent,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.green,
            icon: FontAwesomeIcons.indent),
        _switchTile(context,
            title: 'Auto-Close Pairs',
            subtitle: 'Auto-close ( { [ " \' brackets',
            value: vm.symbolPairAutoClose,
            onChanged: vm.setSymbolPairAutoClose,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.orange,
            icon: FontAwesomeIcons.braille),
        _switchTile(context,
            title: 'Auto-Completion',
            subtitle: 'Code suggestion popup while typing',
            value: vm.autoCompletion,
            onChanged: vm.setAutoCompletion,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.amber,
            icon: FontAwesomeIcons.wandMagicSparkles),
        _switchTile(context,
            title: 'Format on Save',
            subtitle: 'Apply DartFormatter on Ctrl+S',
            value: vm.formatOnSave,
            onChanged: vm.setFormatOnSave,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.wandMagic),
        _switchTile(context,
            title: 'Sticky Scroll',
            subtitle: 'Keep the current scope visible at the top',
            value: vm.stickyScroll,
            onChanged: vm.setStickyScroll,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.brown,
            icon: FontAwesomeIcons.thumbtack),

        // ── Indentation ───────────────────────────────────────────────────
        _sectionHeader('Indentation'),
        _pickerTile(context,
            title: 'Tab Size',
            subtitle: 'Number of spaces per indent level',
            value: vm.tabSize.toString(),
            options: const ['2', '4', '8'],
            onChanged: (v) => vm.setTabSize(int.parse(v)),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.alignLeft),
        _switchTile(context,
            title: 'Use Spaces',
            subtitle: 'Insert spaces instead of tab characters',
            value: vm.useSpaces,
            onChanged: vm.setUseSpaces,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.rulerHorizontal),

        // ── Cursor ────────────────────────────────────────────────────────
        _sectionHeader('Cursor'),
        _sliderTile(context,
            title: 'Cursor Blink Speed',
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
        _sectionHeader('Code Structure'),
        _switchTile(context,
            title: 'Lightbulb Actions',
            subtitle: 'Quick-action icon when code is selected',
            value: vm.showLightbulb,
            onChanged: vm.setShowLightbulb,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.yellow.shade700,
            icon: FontAwesomeIcons.lightbulb),
        _switchTile(context,
            title: 'Fold Arrows',
            subtitle: 'Arrows to collapse code blocks',
            value: vm.showFoldArrows,
            onChanged: vm.setShowFoldArrows,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.angleDown),
        _switchTile(context,
            title: 'Block Lines',
            subtitle: 'Vertical indentation guide lines',
            value: vm.showBlockLines,
            onChanged: vm.setShowBlockLines,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.gripLinesVertical),
        _switchTile(context,
            title: 'Indent Dots',
            subtitle: 'Dots before first character (VS Code style)',
            value: vm.showIndentDots,
            onChanged: vm.setShowIndentDots,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.ellipsis),

        // ── Highlight ─────────────────────────────────────────────────────
        _sectionHeader('Highlight'),
        _switchTile(context,
            title: 'Highlight Current Line',
            subtitle: 'Tint the line where the cursor is',
            value: vm.highlightCurrentLine,
            onChanged: vm.setHighlightCurrentLine,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.highlighter),
        _switchTile(context,
            title: 'Highlight Active Block',
            subtitle: 'Change color inside the active scope',
            value: vm.highlightActiveBlock,
            onChanged: vm.setHighlightActiveBlock,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.borderAll),
        _pickerTile(context,
            title: 'Highlight Style',
            subtitle: 'How the current line is highlighted',
            value: vm.lineHighlightStyle,
            options: const ['fill', 'stroke', 'accentBar', 'none'],
            onChanged: vm.setLineHighlightStyle,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.fillDrip),

        // ── Advanced ──────────────────────────────────────────────────────
        _sectionHeader('Advanced'),
        _switchTile(context,
            title: 'Diagnostic Indicators',
            subtitle: 'Error and warning squiggles',
            value: vm.showDiagnosticIndicators,
            onChanged: vm.setShowDiagnosticIndicators,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.red,
            icon: FontAwesomeIcons.triangleExclamation),
        _switchTile(context,
            title: 'Read Only',
            subtitle: 'Disable all editing in the editor',
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
        title: const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Text('Font Family', style: TextStyle(color: Colors.white, fontSize: 14)),
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
              return AlertDialog(
                title: const Text('Font Family'),
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
          child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
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
        return AlertDialog(
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
                            style: const TextStyle(fontSize: 14, color: Colors.white)),
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
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('File Explorer'),
        _buildOption(context,
            title: 'Show Hidden Files',
            subtitle: 'Display files starting with .',
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
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('Terminal'),
        _buildOption(context,
            title: 'Font Size',
            subtitle: 'Terminal font size',
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal),
        _buildOption(context,
            title: 'Color Scheme',
            subtitle: 'Terminal color theme',
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
        final installed = sdk.installedSdks;
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _sectionHeader('Environment'),
            _infoTile(context,
                title: 'RootFS Path',
                subtitle: RuntimeEnvir.usrPath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folder),
            _infoTile(context,
                title: 'Home Path',
                subtitle: RuntimeEnvir.homePath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.house),
            _infoTile(context,
                title: 'Projects Path',
                subtitle: RuntimeEnvir.projectsPath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folderOpen),
            const SizedBox(height: 16),
            _sectionHeader('Installed SDKs'),
            if (installed.isEmpty)
              _infoTile(context,
                  title: 'No SDKs installed',
                  subtitle: 'Install SDKs from the workspace',
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
                    subtitle: sdk.version(t) ?? 'Installed',
                    borderRadius: BorderRadius.vertical(
                      top: isFirst ? const Radius.circular(30) : const Radius.circular(10),
                      bottom: isLast ? const Radius.circular(30) : const Radius.circular(10),
                    ),
                    iconBg: Colors.orange,
                    icon: FontAwesomeIcons.wrench);
              }),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  // ── AI settings ───────────────────────────────────────────────────────────
  Widget _buildAi(BuildContext context) {
    final ai = context.watch<AiProvider>();

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // ── API Keys ──────────────────────────────────────────────────────
        _sectionHeader('API Keys'),
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
        _sectionHeader('Models'),
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
            Expanded(child: _sectionHeader('Agents')),
            Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 8),
              child: TextButton.icon(
                onPressed: () => _showAgentDialog(context, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New agent'),
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
          child: Text(label, style: const TextStyle(color: Colors.white)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(value.isEmpty ? 'Not configured' : masked, maxLines: 1),
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
          child: Text(label, style: const TextStyle(color: Colors.white)),
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
    final ctrl = TextEditingController(text: current);
    bool obscure = true;
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: Text(label),
            content: TextField(
              controller: ctrl,
              obscureText: obscure,
              decoration: InputDecoration(
                hintText: 'Paste your API key here',
                suffixIcon: IconButton(
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => obscure = !obscure),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () {
                  onSave(ctrl.text.trim());
                  Navigator.pop(ctx);
                },
                child: const Text('Save'),
              ),
            ],
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
              Expanded(child: Text(agent.name, style: const TextStyle(color: Colors.white))),
              if (agent.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Default',
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
              tooltip: 'Edit',
              onPressed: () => _showAgentDialog(context, agent),
            ),
            if (!agent.isDefault)
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Delete',
                onPressed: () => _confirmDeleteAgent(context, agent),
              ),
          ],
        ),
        onTap: () => _showAgentDialog(context, agent),
      ),
    );
  }

  void _confirmDeleteAgent(BuildContext context, AiAgent agent) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete agent'),
        content: Text('Delete "${agent.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<AiProvider>().deleteAgent(agent.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showAgentDialog(BuildContext context, AiAgent? existing) {
    final isNew = existing == null;
    final namectrl  = TextEditingController(text: existing?.name ?? '');
    final focusctrl = TextEditingController(text: existing?.focus ?? '');
    final instrctrl = TextEditingController(text: existing?.instructions ?? '');
    Color avatarColor = Color(existing?.colorValue ?? 0xFF607D8B);

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setState) {
          return AlertDialog(
            title: Text(isNew ? 'New Agent' : 'Edit Agent'),
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
                    decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: focusctrl,
                    decoration: const InputDecoration(labelText: 'Focus area', border: OutlineInputBorder()),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: instrctrl,
                    decoration: const InputDecoration(
                      labelText: 'System instructions',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 6,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
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
                child: Text(isNew ? 'Create' : 'Save'),
              ),
            ],
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
                child: Image.asset('assets/logo.png', width: 80, height: 80, fit: BoxFit.contain),
              ),
              const SizedBox(height: 16),
              const Text(
                'FL IDE',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Mobile Development Environment',
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
        _sectionHeader('Developer'),
        _aboutCard(context,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20), bottom: Radius.circular(6)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: const Color(0xFF1565C0),
              child: const FaIcon(FontAwesomeIcons.code, size: 16, color: Colors.white),
            ),
            title: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Text('Desenvolvedor', style: TextStyle(color: Colors.white)),
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
              child: Text('GitHub', style: TextStyle(color: Colors.white)),
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
        _sectionHeader('SDKs Suportados'),
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
        _sectionHeader('Licença'),
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
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
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
            child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
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
          child: Text(title, style: const TextStyle(color: Colors.white)),
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
          child: Text(title, style: const TextStyle(color: Colors.white)),
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
              child: Text(title, style: const TextStyle(color: Colors.white)),
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
