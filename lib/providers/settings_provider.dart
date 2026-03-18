import 'package:flutter/material.dart';
import 'package:quill_code/quill_code.dart' show EditorProps, LineHighlightStyle;
import 'package:shared_preferences/shared_preferences.dart';

enum SettingsPage {
  main,
  general,
  editor,
  fileExplorer,
  terminal,
  runDebug,
  extensions,
  ai,
  about,
}

class SettingsProvider extends ChangeNotifier {
  // ── General ───────────────────────────────────────────────────────────────
  static const _kFollowSystem      = 'followSystemTheme';
  static const _kUseDarkMode       = 'useDarkMode';
  static const _kUseAmoled         = 'useAmoled';
  static const _kUseDynamicColors  = 'useDynamicColors';

  bool _followSystemTheme  = true;
  bool _useDarkMode        = false;
  bool _useAmoled          = false;
  bool _useDynamicColors   = false;

  // ── Editor ────────────────────────────────────────────────────────────────
  static const _kFontSize                 = 'ed_fontSize';
  static const _kWordWrap                 = 'ed_wordWrap';
  static const _kAutoIndent               = 'ed_autoIndent';
  static const _kSymbolPairAutoClose      = 'ed_symbolPairAutoClose';
  static const _kAutoCompletion           = 'ed_autoCompletion';
  static const _kFormatOnSave             = 'ed_formatOnSave';
  static const _kStickyScroll             = 'ed_stickyScroll';
  static const _kTabSize                  = 'ed_tabSize';
  static const _kUseSpaces               = 'ed_useSpaces';
  static const _kCursorBlinkMs           = 'ed_cursorBlinkMs';
  static const _kShowLineNumbers         = 'ed_showLineNumbers';
  static const _kFixedGutter             = 'ed_fixedGutter';
  static const _kShowMinimap             = 'ed_showMinimap';
  static const _kShowSymbolBar           = 'ed_showSymbolBar';
  static const _kShowLightbulb          = 'ed_showLightbulb';
  static const _kShowFoldArrows         = 'ed_showFoldArrows';
  static const _kShowBlockLines         = 'ed_showBlockLines';
  static const _kShowIndentDots         = 'ed_showIndentDots';
  static const _kHighlightCurrentLine   = 'ed_highlightCurrentLine';
  static const _kHighlightActiveBlock   = 'ed_highlightActiveBlock';
  static const _kLineHighlightStyle     = 'ed_lineHighlightStyle';
  static const _kShowDiagnosticIndicators = 'ed_showDiagnosticIndicators';
  static const _kReadOnly               = 'ed_readOnly';
  static const _kFontFamily             = 'ed_fontFamily';

  double _fontSize               = 14.0;
  bool   _wordWrap               = false;
  bool   _autoIndent             = true;
  bool   _symbolPairAutoClose    = true;
  bool   _autoCompletion         = true;
  bool   _formatOnSave           = false;
  bool   _stickyScroll           = false;
  int    _tabSize                = 4;
  bool   _useSpaces              = true;
  int    _cursorBlinkMs          = 530;
  bool   _showLineNumbers        = true;
  bool   _fixedGutter            = true;
  bool   _showMinimap            = true;
  bool   _showSymbolBar          = true;
  bool   _showLightbulb         = true;
  bool   _showFoldArrows        = true;
  bool   _showBlockLines        = true;
  bool   _showIndentDots        = false;
  bool   _highlightCurrentLine  = true;
  bool   _highlightActiveBlock  = true;
  String _lineHighlightStyle    = 'fill';
  bool   _showDiagnosticIndicators = true;
  bool   _readOnly              = false;
  String _fontFamily            = 'monospace';

  // ── Navigation ────────────────────────────────────────────────────────────
  SettingsPage _currentPage = SettingsPage.main;

  // ── Getters: General ──────────────────────────────────────────────────────
  bool         get followSystemTheme  => _followSystemTheme;
  bool         get useDarkMode        => _useDarkMode;
  bool         get useAmoled          => _useAmoled;
  bool         get useDynamicColors   => _useDynamicColors;

  // ── Getters: Editor ───────────────────────────────────────────────────────
  double get fontSize               => _fontSize;
  bool   get wordWrap               => _wordWrap;
  bool   get autoIndent             => _autoIndent;
  bool   get symbolPairAutoClose    => _symbolPairAutoClose;
  bool   get autoCompletion         => _autoCompletion;
  bool   get formatOnSave           => _formatOnSave;
  bool   get stickyScroll           => _stickyScroll;
  int    get tabSize                => _tabSize;
  bool   get useSpaces              => _useSpaces;
  int    get cursorBlinkMs          => _cursorBlinkMs;
  bool   get showLineNumbers        => _showLineNumbers;
  bool   get fixedGutter            => _fixedGutter;
  bool   get showMinimap            => _showMinimap;
  bool   get showSymbolBar          => _showSymbolBar;
  bool   get showLightbulb         => _showLightbulb;
  bool   get showFoldArrows        => _showFoldArrows;
  bool   get showBlockLines        => _showBlockLines;
  bool   get showIndentDots        => _showIndentDots;
  bool   get highlightCurrentLine  => _highlightCurrentLine;
  bool   get highlightActiveBlock  => _highlightActiveBlock;
  String get lineHighlightStyle    => _lineHighlightStyle;
  bool   get showDiagnosticIndicators => _showDiagnosticIndicators;
  bool   get readOnly              => _readOnly;
  String get fontFamily            => _fontFamily;

  // ── Navigation getter ─────────────────────────────────────────────────────
  SettingsPage get currentPage => _currentPage;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    _followSystemTheme  = p.getBool(_kFollowSystem)      ?? true;
    _useDarkMode        = p.getBool(_kUseDarkMode)       ?? false;
    _useAmoled          = p.getBool(_kUseAmoled)         ?? false;
    _useDynamicColors   = p.getBool(_kUseDynamicColors)  ?? false;

    _fontSize               = p.getDouble(_kFontSize)                ?? 14.0;
    _wordWrap               = p.getBool(_kWordWrap)                  ?? false;
    _autoIndent             = p.getBool(_kAutoIndent)                ?? true;
    _symbolPairAutoClose    = p.getBool(_kSymbolPairAutoClose)       ?? true;
    _autoCompletion         = p.getBool(_kAutoCompletion)            ?? true;
    _formatOnSave           = p.getBool(_kFormatOnSave)              ?? false;
    _stickyScroll           = p.getBool(_kStickyScroll)              ?? false;
    _tabSize                = p.getInt(_kTabSize)                    ?? 4;
    _useSpaces              = p.getBool(_kUseSpaces)                 ?? true;
    _cursorBlinkMs          = p.getInt(_kCursorBlinkMs)              ?? 530;
    _showLineNumbers        = p.getBool(_kShowLineNumbers)           ?? true;
    _fixedGutter            = p.getBool(_kFixedGutter)               ?? true;
    _showMinimap            = p.getBool(_kShowMinimap)               ?? true;
    _showSymbolBar          = p.getBool(_kShowSymbolBar)             ?? true;
    _showLightbulb         = p.getBool(_kShowLightbulb)            ?? true;
    _showFoldArrows        = p.getBool(_kShowFoldArrows)            ?? true;
    _showBlockLines        = p.getBool(_kShowBlockLines)            ?? true;
    _showIndentDots        = p.getBool(_kShowIndentDots)            ?? false;
    _highlightCurrentLine  = p.getBool(_kHighlightCurrentLine)      ?? true;
    _highlightActiveBlock  = p.getBool(_kHighlightActiveBlock)      ?? true;
    _lineHighlightStyle    = p.getString(_kLineHighlightStyle)       ?? 'fill';
    _showDiagnosticIndicators = p.getBool(_kShowDiagnosticIndicators) ?? true;
    _readOnly              = p.getBool(_kReadOnly)                   ?? false;
    _fontFamily            = p.getString(_kFontFamily)               ?? 'monospace';
    notifyListeners();
  }

  // ── Navigation setters ────────────────────────────────────────────────────
  void navigateToPage(SettingsPage page) {
    _currentPage = page;
    notifyListeners();
  }

  void goBack() {
    _currentPage = SettingsPage.main;
    notifyListeners();
  }

  // ── General setters ───────────────────────────────────────────────────────
  Future<void> setFollowSystemTheme(bool val) async {
    _followSystemTheme = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFollowSystem, val);
    notifyListeners();
  }

  Future<void> setUseDarkMode(bool val) async {
    _useDarkMode = val;
    if (val) _followSystemTheme = false;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUseDarkMode, val);
    if (val) await p.setBool(_kFollowSystem, false);
    notifyListeners();
  }

  Future<void> setUseAmoled(bool val) async {
    _useAmoled = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUseAmoled, val);
    notifyListeners();
  }

  Future<void> setUseDynamicColors(bool val) async {
    _useDynamicColors = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUseDynamicColors, val);
    notifyListeners();
  }

  // ── Editor setters ────────────────────────────────────────────────────────
  Future<void> setFontSize(double val) async {
    _fontSize = val;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_kFontSize, val);
    notifyListeners();
  }

  Future<void> setWordWrap(bool val) async {
    _wordWrap = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kWordWrap, val);
    notifyListeners();
  }

  Future<void> setAutoIndent(bool val) async {
    _autoIndent = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoIndent, val);
    notifyListeners();
  }

  Future<void> setSymbolPairAutoClose(bool val) async {
    _symbolPairAutoClose = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kSymbolPairAutoClose, val);
    notifyListeners();
  }

  Future<void> setAutoCompletion(bool val) async {
    _autoCompletion = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAutoCompletion, val);
    notifyListeners();
  }

  Future<void> setFormatOnSave(bool val) async {
    _formatOnSave = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFormatOnSave, val);
    notifyListeners();
  }

  Future<void> setStickyScroll(bool val) async {
    _stickyScroll = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kStickyScroll, val);
    notifyListeners();
  }

  Future<void> setTabSize(int val) async {
    _tabSize = val;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kTabSize, val);
    notifyListeners();
  }

  Future<void> setUseSpaces(bool val) async {
    _useSpaces = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kUseSpaces, val);
    notifyListeners();
  }

  Future<void> setCursorBlinkMs(int val) async {
    _cursorBlinkMs = val;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCursorBlinkMs, val);
    notifyListeners();
  }

  Future<void> setShowLineNumbers(bool val) async {
    _showLineNumbers = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowLineNumbers, val);
    notifyListeners();
  }

  Future<void> setFixedGutter(bool val) async {
    _fixedGutter = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kFixedGutter, val);
    notifyListeners();
  }

  Future<void> setShowMinimap(bool val) async {
    _showMinimap = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowMinimap, val);
    notifyListeners();
  }

  Future<void> setShowSymbolBar(bool val) async {
    _showSymbolBar = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowSymbolBar, val);
    notifyListeners();
  }

  Future<void> setShowLightbulb(bool val) async {
    _showLightbulb = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowLightbulb, val);
    notifyListeners();
  }

  Future<void> setShowFoldArrows(bool val) async {
    _showFoldArrows = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowFoldArrows, val);
    notifyListeners();
  }

  Future<void> setShowBlockLines(bool val) async {
    _showBlockLines = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowBlockLines, val);
    notifyListeners();
  }

  Future<void> setShowIndentDots(bool val) async {
    _showIndentDots = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowIndentDots, val);
    notifyListeners();
  }

  Future<void> setHighlightCurrentLine(bool val) async {
    _highlightCurrentLine = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHighlightCurrentLine, val);
    notifyListeners();
  }

  Future<void> setHighlightActiveBlock(bool val) async {
    _highlightActiveBlock = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kHighlightActiveBlock, val);
    notifyListeners();
  }

  Future<void> setLineHighlightStyle(String val) async {
    _lineHighlightStyle = val;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLineHighlightStyle, val);
    notifyListeners();
  }

  Future<void> setShowDiagnosticIndicators(bool val) async {
    _showDiagnosticIndicators = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kShowDiagnosticIndicators, val);
    notifyListeners();
  }

  Future<void> setReadOnly(bool val) async {
    _readOnly = val;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kReadOnly, val);
    notifyListeners();
  }

  Future<void> setFontFamily(String val) async {
    _fontFamily = val;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kFontFamily, val);
    notifyListeners();
  }

  // ── Apply to EditorProps ──────────────────────────────────────────────────
  /// Mutates [props] in-place with the current editor settings.
  void applyToProps(EditorProps props) {
    props.wordWrap               = _wordWrap;
    props.autoIndent             = _autoIndent;
    props.symbolPairAutoCompletion = _symbolPairAutoClose;
    props.autoCompletion         = _autoCompletion;
    props.formatOnSave           = _formatOnSave;
    props.stickyScroll           = _stickyScroll;
    props.tabSize                = _tabSize;
    props.useSpacesForTabs       = _useSpaces;
    props.cursorBlinkIntervalMs  = _cursorBlinkMs;
    props.showLineNumbers        = _showLineNumbers;
    props.fixedLineNumbers       = _fixedGutter;
    props.showMinimap            = _showMinimap;
    props.showLightbulb         = _showLightbulb;
    props.showFoldArrows        = _showFoldArrows;
    props.showBlockLines        = _showBlockLines;
    props.highlightCurrentLine  = _highlightCurrentLine;
    props.highlightActiveBlock  = _highlightActiveBlock;
    props.lineHighlightStyle    = _parseLineHighlightStyle(_lineHighlightStyle);
    props.showDiagnosticIndicators = _showDiagnosticIndicators;
    props.readOnly              = _readOnly;
  }

  static LineHighlightStyle _parseLineHighlightStyle(String s) {
    switch (s) {
      case 'stroke':    return LineHighlightStyle.stroke;
      case 'accentBar': return LineHighlightStyle.accentBar;
      case 'none':      return LineHighlightStyle.none;
      default:          return LineHighlightStyle.fill;
    }
  }
}
