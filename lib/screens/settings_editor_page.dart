import 'dart:ui';

import 'package:build_runner_pkg/build_runner_pkg.dart'
    show BuildPlatform, supportedPlatforms;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';

import '../app.dart' show showThemedDialog;
import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class EditorSettingsPage extends StatelessWidget {
  const EditorSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final vm = context.watch<SettingsProvider>();

    return SettingsPageScaffold(
      title: s.editor,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
                  settingsSectionHeader(context,s.secFontDisplay),
          Stack(
            children: [
              _fontPickerTile(context, vm),
              Positioned(
                top: 4,
                right: 4,
                child: settingsInfoButton(context, s.fontFamily, s.fontFamilyInfo),
              ),
            ],
          ),
          settingsSliderTile(
            context,
            title: s.fontSize,
            value: vm.fontSize,
            min: 8,
            max: 32,
            valueLabel: '${vm.fontSize.round()}px',
            onChanged: (v) => vm.setFontSize(v.roundToDouble()),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.blue,
            icon: FontAwesomeIcons.font,
            divisions: 17,
            infoText: s.fontSizeInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.lineNumbers,
            subtitle: s.lineNumbersSub,
            value: vm.showLineNumbers,
            onChanged: vm.setShowLineNumbers,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.listOl,
            infoText: s.lineNumbersInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.fixedGutter,
            subtitle: s.fixedGutterSub,
            value: vm.fixedGutter,
            onChanged: vm.setFixedGutter,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.tableColumns,
            infoText: s.fixedGutterInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.minimap,
            subtitle: s.minimapSub,
            value: vm.showMinimap,
            onChanged: vm.setShowMinimap,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.map,
            infoText: s.minimapInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.symbolBar,
            subtitle: s.symbolBarSub,
            value: vm.showSymbolBar,
            onChanged: vm.setShowSymbolBar,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.keyboard,
            infoText: s.symbolBarInfo,
          ),

                  settingsSectionHeader(context,s.secBehavior),
          settingsSwitchTile(
            context,
            title: s.wordWrap,
            subtitle: s.wordWrapSub,
            value: vm.wordWrap,
            onChanged: vm.setWordWrap,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.alignJustify,
            infoText: s.wordWrapInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.autoIndent,
            subtitle: s.autoIndentSub,
            value: vm.autoIndent,
            onChanged: vm.setAutoIndent,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.green,
            icon: FontAwesomeIcons.indent,
            infoText: s.autoIndentInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.autoClosePairs,
            subtitle: s.autoClosePairsSub,
            value: vm.symbolPairAutoClose,
            onChanged: vm.setSymbolPairAutoClose,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.orange,
            icon: FontAwesomeIcons.braille,
            infoText: s.autoClosePairsInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.autoCompletion,
            subtitle: s.autoCompletionSub,
            value: vm.autoCompletion,
            onChanged: vm.setAutoCompletion,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.amber,
            icon: FontAwesomeIcons.wandMagicSparkles,
            infoText: s.autoCompletionInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.formatOnSave,
            subtitle: s.formatOnSaveSub,
            value: vm.formatOnSave,
            onChanged: vm.setFormatOnSave,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.wandMagic,
            infoText: s.formatOnSaveInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.stickyScroll,
            subtitle: s.stickyScrollSub,
            value: vm.stickyScroll,
            onChanged: vm.setStickyScroll,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.brown,
            icon: FontAwesomeIcons.thumbtack,
            infoText: s.stickyScrollInfo,
          ),

                  settingsSectionHeader(context,s.secIndentation),
          settingsPickerTile(
            context,
            title: s.tabSize,
            subtitle: s.tabSizeSub,
            value: vm.tabSize.toString(),
            options: const ['2', '4', '8'],
            onChanged: (v) => vm.setTabSize(int.parse(v)),
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.alignLeft,
            infoText: s.tabSizeInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.useSpaces,
            subtitle: s.useSpacesSub,
            value: vm.useSpaces,
            onChanged: vm.setUseSpaces,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.rulerHorizontal,
            infoText: s.useSpacesInfo,
          ),

                 settingsSectionHeader(context,s.secCursor),
          settingsSliderTile(
            context,
            title: s.cursorBlinkSpeed,
            value: vm.cursorBlinkMs.toDouble(),
            min: 200,
            max: 1000,
            valueLabel: '${vm.cursorBlinkMs}ms',
            onChanged: (v) => vm.setCursorBlinkMs(v.round()),
            borderRadius: const BorderRadius.all(Radius.circular(30)),
            iconBg: Colors.deepOrange,
            icon: FontAwesomeIcons.iCursor,
            divisions: 8,
            infoText: s.cursorBlinkSpeedInfo,
          ),

                  settingsSectionHeader(context,s.secCodeStructure),
          settingsSwitchTile(
            context,
            title: s.lightbulbActions,
            subtitle: s.lightbulbActionsSub,
            value: vm.showLightbulb,
            onChanged: vm.setShowLightbulb,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.yellow.shade700,
            icon: FontAwesomeIcons.lightbulb,
            infoText: s.lightbulbActionsInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.foldArrows,
            subtitle: s.foldArrowsSub,
            value: vm.showFoldArrows,
            onChanged: vm.setShowFoldArrows,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.angleDown,
            infoText: s.foldArrowsInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.blockLines,
            subtitle: s.blockLinesSub,
            value: vm.showBlockLines,
            onChanged: vm.setShowBlockLines,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.gripLinesVertical,
            infoText: s.blockLinesInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.indentDots,
            subtitle: s.indentDotsSub,
            value: vm.showIndentDots,
            onChanged: vm.setShowIndentDots,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.deepPurple,
            icon: FontAwesomeIcons.ellipsis,
            infoText: s.indentDotsInfo,
          ),

                  settingsSectionHeader(context,s.secHighlight),
          settingsSwitchTile(
            context,
            title: s.highlightCurrentLine,
            subtitle: s.highlightCurrentLineSub,
            value: vm.highlightCurrentLine,
            onChanged: vm.setHighlightCurrentLine,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.highlighter,
            infoText: s.highlightCurrentLineInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.highlightActiveBlock,
            subtitle: s.highlightActiveBlockSub,
            value: vm.highlightActiveBlock,
            onChanged: vm.setHighlightActiveBlock,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.borderAll,
            infoText: s.highlightActiveBlockInfo,
          ),
          settingsPickerTile(
            context,
            title: s.highlightStyle,
            subtitle: s.highlightStyleSub,
            value: vm.lineHighlightStyle,
            options: const ['fill', 'stroke', 'accentBar', 'none'],
            onChanged: vm.setLineHighlightStyle,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.pinkAccent,
            icon: FontAwesomeIcons.fillDrip,
            infoText: s.highlightStyleInfo,
          ),

                  settingsSectionHeader(context,s.secAdvanced),
          settingsSwitchTile(
            context,
            title: s.diagnosticIndicators,
            subtitle: s.diagnosticIndicatorsSub,
            value: vm.showDiagnosticIndicators,
            onChanged: vm.setShowDiagnosticIndicators,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(30),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.red,
            icon: FontAwesomeIcons.triangleExclamation,
            infoText: s.diagnosticIndicatorsInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.editorStatusBar,
            subtitle: s.editorStatusBarSub,
            value: vm.showEditorStatusBar,
            onChanged: vm.setShowEditorStatusBar,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(5),
            ),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.bars,
            infoText: s.editorStatusBarInfo,
          ),
          settingsSwitchTile(
            context,
            title: s.readOnly,
            subtitle: s.readOnlySub,
            value: vm.readOnly,
            onChanged: vm.setReadOnly,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(5),
              bottom: Radius.circular(30),
            ),
            iconBg: Colors.grey,
            icon: FontAwesomeIcons.lock,
            infoText: s.readOnlyInfo,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

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
     final card = Theme.of(context).cardTheme;
    return Card(
   //   elevation: 0,
    // color: card.color?.withOpacity(0.5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(5)),
      ),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.deepOrange,
          child: FaIcon(FontAwesomeIcons.font, size: 16, color: Colors.white),
        ),
        title: Text(AppStrings.of(context).fontFamily),
        subtitle: Text(currentLabel),
       // trailing: const Icon(Icons.chevron_right),
        onTap: () {
          showThemedDialog<void>(
            context: context,
            title: AppStrings.of(context).fontFamily,
            builder: (ctx) {
              return  Column(
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
                         // color: Colors.grey,
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
                
              );
            },
          );
        },
      ),
    );
  }
}
