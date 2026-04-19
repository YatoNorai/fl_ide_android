import 'dart:convert';

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
  ssh,
  about,
}

class SettingsProvider extends ChangeNotifier {
  // ── Static warm-up cache ──────────────────────────────────────────────────
  /// Populated by [warmUp] in main() before runApp so the constructor can
  /// initialise synchronously, eliminating the theme flash on first build.
  static SharedPreferences? _warmPrefs;

  /// Call once in main() before runApp to pre-warm SharedPreferences.
  static Future<void> warmUp() async {
    _warmPrefs = await SharedPreferences.getInstance();
  }
  // ── General ───────────────────────────────────────────────────────────────
  static const _kFollowSystem      = 'followSystemTheme';
  static const _kUseDarkMode       = 'useDarkMode';
  static const _kUseAmoled         = 'useAmoled';
  static const _kUseDynamicColors  = 'useDynamicColors';
  static const _kLiquidGlass       = 'liquidGlass';
  static const _kImmersiveScroll   = 'immersiveScroll';

  bool _followSystemTheme  = true;
  bool _useDarkMode        = false;
  bool _useAmoled          = false;
  bool _useDynamicColors   = true;
  bool _liquidGlass        = false;
  bool _immersiveScroll    = true;

  // ── Editor ────────────────────────────────────────────────────────────────
  static const _kFontSize                 = 'ed_fontSize';
  static const _kWordWrap                 = 'ed_wordWrap';
  static const _kAutoIndent               = 'ed_autoIndent';
  static const _kSymbolPairAutoClose      = 'ed_symbolPairAutoClose';
  static const _kAutoCompletion           = 'ed_autoCompletion';
  static const _kFormatOnSave             = 'ed_formatOnSave';
  static const _kOrganizeImportsOnSave    = 'ed_organizeImportsOnSave';
  static const _kFixAllOnSave             = 'ed_fixAllOnSave';
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
  static const _kShowEditorStatusBar      = 'ed_showStatusBar';
  static const _kReadOnly               = 'ed_readOnly';
  static const _kFontFamily             = 'ed_fontFamily';

  double _fontSize               = 14.0;
  bool   _wordWrap               = false;
  bool   _autoIndent             = true;
  bool   _symbolPairAutoClose    = true;
  bool   _autoCompletion         = true;
  bool   _formatOnSave           = false;
  bool   _organizeImportsOnSave  = false;
  bool   _fixAllOnSave           = false;
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
  bool   _showEditorStatusBar      = true;
  bool   _readOnly              = false;
  String _fontFamily            = 'monospace';

  // ── Run & Debug ───────────────────────────────────────────────────────────
  static const _kLspPaths = 'rd_lspPaths';
  static const _kDebugPlatforms = 'rd_debugPlatforms';
  Map<String, String> _lspPaths = {};
  /// sdkTypeName → buildPlatformName (e.g. 'flutter' → 'android')
  Map<String, String> _debugPlatforms = {};

  // ── Language ──────────────────────────────────────────────────────────────
  static const _kLanguage = 'language';
  /// Empty string means follow device locale.
  String _language = '';

  // ── Onboarding ────────────────────────────────────────────────────────────
  static const _kOnboardingDone = 'onboardingDone';
  bool _onboardingDone = false;
  bool _loaded = false;

  // ── Navigation ────────────────────────────────────────────────────────────
  SettingsPage _currentPage = SettingsPage.main;

  // ── Getters: General ──────────────────────────────────────────────────────
  bool         get followSystemTheme  => _followSystemTheme;
  bool         get useDarkMode        => _useDarkMode;
  bool         get useAmoled          => _useAmoled;
  bool         get useDynamicColors   => _useDynamicColors;
  bool         get liquidGlass        => _liquidGlass;
  bool         get immersiveScroll    => _immersiveScroll;

  // ── Getters: Editor ───────────────────────────────────────────────────────
  double get fontSize               => _fontSize;
  bool   get wordWrap               => _wordWrap;
  bool   get autoIndent             => _autoIndent;
  bool   get symbolPairAutoClose    => _symbolPairAutoClose;
  bool   get autoCompletion         => _autoCompletion;
  bool   get formatOnSave           => _formatOnSave;
  bool   get organizeImportsOnSave  => _organizeImportsOnSave;
  bool   get fixAllOnSave           => _fixAllOnSave;
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
  bool   get showEditorStatusBar      => _showEditorStatusBar;
  bool   get readOnly              => _readOnly;
  String get fontFamily            => _fontFamily;

  /// A snapshot of all editor-config fields used by [applyToProps] plus
  /// [fontSize] / [fontFamily].  Returned as a record so [context.select]
  /// can compare it by value and skip rebuilds when unrelated settings change.
  ({
    double fontSize,
    String fontFamily,
    bool wordWrap,
    bool autoIndent,
    bool symbolPairAutoClose,
    bool autoCompletion,
    bool formatOnSave,
    bool organizeImportsOnSave,
    bool fixAllOnSave,
    bool stickyScroll,
    int tabSize,
    bool useSpaces,
    int cursorBlinkMs,
    bool showLineNumbers,
    bool fixedGutter,
    bool showMinimap,
    bool showLightbulb,
    bool showFoldArrows,
    bool showBlockLines,
    bool highlightCurrentLine,
    bool highlightActiveBlock,
    String lineHighlightStyle,
    bool showDiagnosticIndicators,
    bool showEditorStatusBar,
    bool readOnly,
  }) get editorConfigSnapshot => (
    fontSize:                _fontSize,
    fontFamily:              _fontFamily,
    wordWrap:                _wordWrap,
    autoIndent:              _autoIndent,
    symbolPairAutoClose:     _symbolPairAutoClose,
    autoCompletion:          _autoCompletion,
    formatOnSave:            _formatOnSave,
    organizeImportsOnSave:   _organizeImportsOnSave,
    fixAllOnSave:            _fixAllOnSave,
    stickyScroll:            _stickyScroll,
    tabSize:                 _tabSize,
    useSpaces:               _useSpaces,
    cursorBlinkMs:           _cursorBlinkMs,
    showLineNumbers:         _showLineNumbers,
    fixedGutter:             _fixedGutter,
    showMinimap:             _showMinimap,
    showLightbulb:           _showLightbulb,
    showFoldArrows:          _showFoldArrows,
    showBlockLines:          _showBlockLines,
    highlightCurrentLine:    _highlightCurrentLine,
    highlightActiveBlock:    _highlightActiveBlock,
    lineHighlightStyle:      _lineHighlightStyle,
    showDiagnosticIndicators: _showDiagnosticIndicators,
    showEditorStatusBar:     _showEditorStatusBar,
    readOnly:                _readOnly,
  );

  // ── Getters: Run & Debug ──────────────────────────────────────────────────
  Map<String, String> get lspPaths => Map.unmodifiable(_lspPaths);
  String lspPathFor(String ext) => _lspPaths[ext.toLowerCase()] ?? '';
  Map<String, String> get debugPlatforms => Map.unmodifiable(_debugPlatforms);
  /// Returns the saved debug platform name for a given SDK type name, or null.
  String? debugPlatformFor(String sdkTypeName) => _debugPlatforms[sdkTypeName];

  // ── Getters: Language ─────────────────────────────────────────────────────
  /// Empty string = device locale. Otherwise a language code like 'en', 'pt'.
  String get language => _language;
  Locale? get languageLocale =>
      _language.isEmpty ? null : Locale(_language);

  // ── Getters: Onboarding ───────────────────────────────────────────────────
  bool get onboardingDone => _onboardingDone;
  bool get isLoaded => _loaded;

  // ── Navigation getter ─────────────────────────────────────────────────────
  SettingsPage get currentPage => _currentPage;

  /// Cached SharedPreferences instance — avoids re-acquiring on every setter.
  SharedPreferences? _prefs;

  /// Returns the cached prefs, acquiring once if not yet available.
  Future<SharedPreferences> _getPrefs() async =>
      _prefs ??= await _getPrefs();

  SettingsProvider() {
    if (_warmPrefs != null) {
      _prefs = _warmPrefs; // reuse the pre-warmed instance
      _loadFrom(_warmPrefs!);
      // _loaded already set to true; no notifyListeners needed in constructor
    } else {
      _loadAsync();
    }
  }

  /// Synchronous init from pre-warmed prefs (called from constructor).
  void _loadFrom(SharedPreferences p) {
    _applyPrefs(p);
    _loaded = true;
    // Don't call notifyListeners() — widget tree not yet attached.
  }

  Future<void> _loadAsync() async {
    final p = await _getPrefs();
    _applyPrefs(p);
    _loaded = true;
    notifyListeners();
  }

  void _applyPrefs(SharedPreferences p) {
    _followSystemTheme  = p.getBool(_kFollowSystem)      ?? true;
    _useDarkMode        = p.getBool(_kUseDarkMode)       ?? false;
    _useAmoled          = p.getBool(_kUseAmoled)         ?? false;
    _useDynamicColors   = p.getBool(_kUseDynamicColors)  ?? true;
    _liquidGlass        = p.getBool(_kLiquidGlass)       ?? false;
    _immersiveScroll    = p.getBool(_kImmersiveScroll)   ?? true;

    _fontSize               = p.getDouble(_kFontSize)                ?? 14.0;
    _wordWrap               = p.getBool(_kWordWrap)                  ?? false;
    _autoIndent             = p.getBool(_kAutoIndent)                ?? true;
    _symbolPairAutoClose    = p.getBool(_kSymbolPairAutoClose)       ?? true;
    _autoCompletion         = p.getBool(_kAutoCompletion)            ?? true;
    _formatOnSave           = p.getBool(_kFormatOnSave)              ?? false;
    _organizeImportsOnSave  = p.getBool(_kOrganizeImportsOnSave)     ?? false;
    _fixAllOnSave           = p.getBool(_kFixAllOnSave)              ?? false;
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
    _showEditorStatusBar      = p.getBool(_kShowEditorStatusBar)      ?? true;
    _readOnly              = p.getBool(_kReadOnly)                   ?? false;
    _fontFamily            = p.getString(_kFontFamily)               ?? 'monospace';

    final lspJson = p.getString(_kLspPaths);
    if (lspJson != null) {
      try {
        final m = jsonDecode(lspJson) as Map<String, dynamic>;
        _lspPaths = m.map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }

    final dpJson = p.getString(_kDebugPlatforms);
    if (dpJson != null) {
      try {
        final m = jsonDecode(dpJson) as Map<String, dynamic>;
        _debugPlatforms = m.map((k, v) => MapEntry(k, v as String));
      } catch (_) {}
    }

    _language       = p.getString(_kLanguage)       ?? '';
    _onboardingDone = p.getBool(_kOnboardingDone)   ?? false;

    _sshEnabled      = p.getBool(_kSshEnabled)             ?? false;
    _sshHost         = p.getString(_kSshHost)               ?? '';
    _sshPort         = p.getInt(_kSshPort)                   ?? 22;
    _sshUsername     = p.getString(_kSshUsername)           ?? '';
    _sshPassword     = p.getString(_kSshPassword)           ?? '';
    _sshKeyPath      = p.getString(_kSshKeyPath)            ?? '';
    _sshUseKey       = p.getBool(_kSshUseKey)               ?? false;
    _sshProjectsPath = p.getString(_kSshProjectsPath)       ?? '';

    _remoteGitBuild = p.getBool(_kRemoteGitBuild)  ?? false;
    _githubToken    = p.getString(_kGithubToken)    ?? '';
  }

  // ── Language setters ──────────────────────────────────────────────────────
  Future<void> setLanguage(String langCode) async {
    _language = langCode;
    final p = await _getPrefs();
    await p.setString(_kLanguage, langCode);
    notifyListeners();
  }

  // ── Onboarding setters ────────────────────────────────────────────────────
  Future<void> setOnboardingDone() async {
    _onboardingDone = true;
    final p = await _getPrefs();
    await p.setBool(_kOnboardingDone, true);
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
    final p = await _getPrefs();
    await p.setBool(_kFollowSystem, val);
    notifyListeners();
  }

  Future<void> setUseDarkMode(bool val) async {
    _useDarkMode = val;
    if (val) _followSystemTheme = false;
    final p = await _getPrefs();
    await p.setBool(_kUseDarkMode, val);
    if (val) await p.setBool(_kFollowSystem, false);
    notifyListeners();
  }

  Future<void> setUseAmoled(bool val) async {
    _useAmoled = val;
    final p = await _getPrefs();
    await p.setBool(_kUseAmoled, val);
    notifyListeners();
  }

  Future<void> setUseDynamicColors(bool val) async {
    _useDynamicColors = val;
    final p = await _getPrefs();
    await p.setBool(_kUseDynamicColors, val);
    notifyListeners();
  }

  Future<void> setLiquidGlass(bool val) async {
    _liquidGlass = val;
    final p = await _getPrefs();
    await p.setBool(_kLiquidGlass, val);
    notifyListeners();
  }

  Future<void> setImmersiveScroll(bool val) async {
    _immersiveScroll = val;
    final p = await _getPrefs();
    await p.setBool(_kImmersiveScroll, val);
    notifyListeners();
  }

  // ── Editor setters ────────────────────────────────────────────────────────
  Future<void> setFontSize(double val) async {
    _fontSize = val;
    final p = await _getPrefs();
    await p.setDouble(_kFontSize, val);
    notifyListeners();
  }

  Future<void> setWordWrap(bool val) async {
    _wordWrap = val;
    final p = await _getPrefs();
    await p.setBool(_kWordWrap, val);
    notifyListeners();
  }

  Future<void> setAutoIndent(bool val) async {
    _autoIndent = val;
    final p = await _getPrefs();
    await p.setBool(_kAutoIndent, val);
    notifyListeners();
  }

  Future<void> setSymbolPairAutoClose(bool val) async {
    _symbolPairAutoClose = val;
    final p = await _getPrefs();
    await p.setBool(_kSymbolPairAutoClose, val);
    notifyListeners();
  }

  Future<void> setAutoCompletion(bool val) async {
    _autoCompletion = val;
    final p = await _getPrefs();
    await p.setBool(_kAutoCompletion, val);
    notifyListeners();
  }

  Future<void> setFormatOnSave(bool val) async {
    _formatOnSave = val;
    final p = await _getPrefs();
    await p.setBool(_kFormatOnSave, val);
    notifyListeners();
  }

  Future<void> setOrganizeImportsOnSave(bool val) async {
    _organizeImportsOnSave = val;
    final p = await _getPrefs();
    await p.setBool(_kOrganizeImportsOnSave, val);
    notifyListeners();
  }

  Future<void> setFixAllOnSave(bool val) async {
    _fixAllOnSave = val;
    final p = await _getPrefs();
    await p.setBool(_kFixAllOnSave, val);
    notifyListeners();
  }

  Future<void> setStickyScroll(bool val) async {
    _stickyScroll = val;
    final p = await _getPrefs();
    await p.setBool(_kStickyScroll, val);
    notifyListeners();
  }

  Future<void> setTabSize(int val) async {
    _tabSize = val;
    final p = await _getPrefs();
    await p.setInt(_kTabSize, val);
    notifyListeners();
  }

  Future<void> setUseSpaces(bool val) async {
    _useSpaces = val;
    final p = await _getPrefs();
    await p.setBool(_kUseSpaces, val);
    notifyListeners();
  }

  Future<void> setCursorBlinkMs(int val) async {
    _cursorBlinkMs = val;
    final p = await _getPrefs();
    await p.setInt(_kCursorBlinkMs, val);
    notifyListeners();
  }

  Future<void> setShowLineNumbers(bool val) async {
    _showLineNumbers = val;
    final p = await _getPrefs();
    await p.setBool(_kShowLineNumbers, val);
    notifyListeners();
  }

  Future<void> setFixedGutter(bool val) async {
    _fixedGutter = val;
    final p = await _getPrefs();
    await p.setBool(_kFixedGutter, val);
    notifyListeners();
  }

  Future<void> setShowMinimap(bool val) async {
    _showMinimap = val;
    final p = await _getPrefs();
    await p.setBool(_kShowMinimap, val);
    notifyListeners();
  }

  Future<void> setShowSymbolBar(bool val) async {
    _showSymbolBar = val;
    final p = await _getPrefs();
    await p.setBool(_kShowSymbolBar, val);
    notifyListeners();
  }

  Future<void> setShowLightbulb(bool val) async {
    _showLightbulb = val;
    final p = await _getPrefs();
    await p.setBool(_kShowLightbulb, val);
    notifyListeners();
  }

  Future<void> setShowFoldArrows(bool val) async {
    _showFoldArrows = val;
    final p = await _getPrefs();
    await p.setBool(_kShowFoldArrows, val);
    notifyListeners();
  }

  Future<void> setShowBlockLines(bool val) async {
    _showBlockLines = val;
    final p = await _getPrefs();
    await p.setBool(_kShowBlockLines, val);
    notifyListeners();
  }

  Future<void> setShowIndentDots(bool val) async {
    _showIndentDots = val;
    final p = await _getPrefs();
    await p.setBool(_kShowIndentDots, val);
    notifyListeners();
  }

  Future<void> setHighlightCurrentLine(bool val) async {
    _highlightCurrentLine = val;
    final p = await _getPrefs();
    await p.setBool(_kHighlightCurrentLine, val);
    notifyListeners();
  }

  Future<void> setHighlightActiveBlock(bool val) async {
    _highlightActiveBlock = val;
    final p = await _getPrefs();
    await p.setBool(_kHighlightActiveBlock, val);
    notifyListeners();
  }

  Future<void> setLineHighlightStyle(String val) async {
    _lineHighlightStyle = val;
    final p = await _getPrefs();
    await p.setString(_kLineHighlightStyle, val);
    notifyListeners();
  }

  Future<void> setShowDiagnosticIndicators(bool val) async {
    _showDiagnosticIndicators = val;
    final p = await _getPrefs();
    await p.setBool(_kShowDiagnosticIndicators, val);
    notifyListeners();
  }

  Future<void> setShowEditorStatusBar(bool val) async {
    _showEditorStatusBar = val;
    final p = await _getPrefs();
    await p.setBool(_kShowEditorStatusBar, val);
    notifyListeners();
  }

  Future<void> setReadOnly(bool val) async {
    _readOnly = val;
    final p = await _getPrefs();
    await p.setBool(_kReadOnly, val);
    notifyListeners();
  }

  Future<void> setFontFamily(String val) async {
    _fontFamily = val;
    final p = await _getPrefs();
    await p.setString(_kFontFamily, val);
    notifyListeners();
  }

  // ── Run & Debug setters ───────────────────────────────────────────────────
  Future<void> setDebugPlatform(String sdkTypeName, String platformName) async {
    _debugPlatforms[sdkTypeName] = platformName;
    final p = await _getPrefs();
    await p.setString(_kDebugPlatforms, jsonEncode(_debugPlatforms));
    notifyListeners();
  }

  Future<void> setLspPath(String ext, String path) async {
    if (path.trim().isEmpty) {
      _lspPaths.remove(ext.toLowerCase());
    } else {
      _lspPaths[ext.toLowerCase()] = path.trim();
    }
    final p = await _getPrefs();
    await p.setString(_kLspPaths, jsonEncode(_lspPaths));
    notifyListeners();
  }

  // ── Apply to EditorProps ──────────────────────────────────────────────────
  void applyToProps(EditorProps props) {
    props.wordWrap               = _wordWrap;
    props.autoIndent             = _autoIndent;
    props.symbolPairAutoCompletion = _symbolPairAutoClose;
    props.autoCompletion         = _autoCompletion;
    props.formatOnSave           = _formatOnSave;
    props.organizeImportsOnSave  = _organizeImportsOnSave;
    props.fixAllOnSave           = _fixAllOnSave;
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
    props.showStatusBar            = _showEditorStatusBar;
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

  // ── SSH ───────────────────────────────────────────────────────────────────
  static const _kSshEnabled      = 'ssh_enabled';
  static const _kSshHost         = 'ssh_host';
  static const _kSshPort         = 'ssh_port';
  static const _kSshUsername     = 'ssh_username';
  static const _kSshPassword     = 'ssh_password';
  static const _kSshKeyPath      = 'ssh_keyPath';
  static const _kSshUseKey       = 'ssh_useKey';
  static const _kSshProjectsPath = 'ssh_projectsPath';

  bool   _sshEnabled      = false;
  String _sshHost         = '';
  int    _sshPort         = 22;
  String _sshUsername     = '';
  String _sshPassword     = '';
  String _sshKeyPath      = '';
  bool   _sshUseKey       = false;
  String _sshProjectsPath = '';

  bool   get sshEnabled      => _sshEnabled;
  String get sshHost         => _sshHost;
  int    get sshPort         => _sshPort;
  String get sshUsername     => _sshUsername;
  String get sshPassword     => _sshPassword;
  String get sshKeyPath      => _sshKeyPath;
  bool   get sshUseKey       => _sshUseKey;
  String get sshProjectsPath => _sshProjectsPath;

  Future<void> setSshEnabled(bool v) async {
    _sshEnabled = v;
    final p = await _getPrefs();
    await p.setBool(_kSshEnabled, v);
    notifyListeners();
  }

  Future<void> setSshHost(String v) async {
    _sshHost = v;
    final p = await _getPrefs();
    await p.setString(_kSshHost, v);
    notifyListeners();
  }

  Future<void> setSshPort(int v) async {
    _sshPort = v;
    final p = await _getPrefs();
    await p.setInt(_kSshPort, v);
    notifyListeners();
  }

  Future<void> setSshUsername(String v) async {
    _sshUsername = v;
    final p = await _getPrefs();
    await p.setString(_kSshUsername, v);
    notifyListeners();
  }

  Future<void> setSshPassword(String v) async {
    _sshPassword = v;
    final p = await _getPrefs();
    await p.setString(_kSshPassword, v);
    notifyListeners();
  }

  Future<void> setSshKeyPath(String v) async {
    _sshKeyPath = v;
    final p = await _getPrefs();
    await p.setString(_kSshKeyPath, v);
    notifyListeners();
  }

  Future<void> setSshUseKey(bool v) async {
    _sshUseKey = v;
    final p = await _getPrefs();
    await p.setBool(_kSshUseKey, v);
    notifyListeners();
  }

  Future<void> setSshProjectsPath(String v) async {
    _sshProjectsPath = v;
    final p = await _getPrefs();
    await p.setString(_kSshProjectsPath, v);
    notifyListeners();
  }

  // ── Remote Git Build ──────────────────────────────────────────────────────
  static const _kRemoteGitBuild = 'git_remoteBuild';
  static const _kGithubToken   = 'git_githubToken';

  bool   _remoteGitBuild = false;
  String _githubToken   = '';

  bool   get remoteGitBuild => _remoteGitBuild;
  String get githubToken    => _githubToken;

  Future<void> setRemoteGitBuild(bool v) async {
    _remoteGitBuild = v;
    final p = await _getPrefs();
    await p.setBool(_kRemoteGitBuild, v);
    notifyListeners();
  }

  Future<void> setGithubToken(String v) async {
    _githubToken = v.trim();
    final p = await _getPrefs();
    await p.setString(_kGithubToken, v.trim());
    notifyListeners();
  }
}
