import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:quill_code/quill_code.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/extension_theme_meta.dart';

const _kRawBase =
    'https://raw.githubusercontent.com/YatoNorai/fl_ide_android/main/extensions/';
const _kThemeRawBase = '${_kRawBase}themes/';
const _kSdkRawBase   = '${_kRawBase}sdk/';

const _kPrefInstalled = 'ext_installed_ids';
const _kPrefActive = 'ext_active_theme_id';

class ExtensionsProvider extends ChangeNotifier {
  // ── State ────────────────────────────────────────────────────────────────
  List<ExtensionThemeMeta> _available = [];
  final Map<String, ExtensionThemeMeta> _installed = {};
  String? _activeId;
  EditorTheme? _activeEditorTheme;

  bool _loadingIndex = false;
  String? _indexError;
  final Set<String> _downloading = {};

  // SDK extensions
  List<SdkExtension> _availableSdks = [];
  bool _loadingSdkIndex = false;
  String? _sdkIndexError;

  // ── Getters ──────────────────────────────────────────────────────────────
  List<ExtensionThemeMeta> get availableThemes => _available;
  List<ExtensionThemeMeta> get installedThemes =>
      _installed.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
  String? get activeThemeId => _activeId;
  EditorTheme? get activeEditorTheme => _activeEditorTheme;
  ExtensionThemeMeta? get activeMeta =>
      _activeId == null ? null : _installed[_activeId];
  bool get loadingIndex => _loadingIndex;
  String? get indexError => _indexError;
  bool isInstalled(String id) => _installed.containsKey(id);
  bool isDownloading(String id) => _downloading.contains(id);
  bool isActive(String id) => _activeId == id;

  List<SdkExtension> get availableSdks => _availableSdks;
  bool get loadingSdkIndex => _loadingSdkIndex;
  String? get sdkIndexError => _sdkIndexError;

  ExtensionsProvider() {
    _init();
  }

  // ── Init ─────────────────────────────────────────────────────────────────
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final installedIds =
        prefs.getStringList(_kPrefInstalled) ?? [];
    final dir = await _themesDir();

    // Load installed theme metas from disk
    for (final id in installedIds) {
      final file = File('${dir.path}/$id.json');
      if (await file.exists()) {
        try {
          final json =
              jsonDecode(await file.readAsString()) as Map<String, dynamic>;
          _installed[id] = ExtensionThemeMeta.fromJson(json);
        } catch (_) {}
      }
    }

    // Restore active theme
    _activeId = prefs.getString(_kPrefActive);
    if (_activeId != null && _installed.containsKey(_activeId)) {
      await _loadActiveEditorTheme(_activeId!);
    } else {
      _activeId = null;
    }

    notifyListeners();
    fetchIndex();
    fetchSdkIndex();
  }

  // ── Fetch index (from GitHub) ────────────────────────────────────────────
  Future<void> fetchIndex() async {
    _loadingIndex = true;
    _indexError = null;
    notifyListeners();

    try {
      final resp = await http
          .get(Uri.parse('${_kThemeRawBase}index.json'))
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final list = json['themes'] as List<dynamic>;
      _available = list
          .map((e) => ExtensionThemeMeta.fromJson(e as Map<String, dynamic>))
          .toList();
      _indexError = null;
    } catch (e) {
      _indexError = 'Could not load theme list: $e';
    }

    _loadingIndex = false;
    notifyListeners();
  }

  // ── Fetch SDK index (from GitHub) ────────────────────────────────────────
  Future<void> fetchSdkIndex() async {
    _loadingSdkIndex = true;
    _sdkIndexError = null;
    notifyListeners();

    try {
      final indexResp = await http
          .get(Uri.parse('${_kSdkRawBase}index.json'))
          .timeout(const Duration(seconds: 15));

      if (indexResp.statusCode != 200) {
        throw Exception('HTTP ${indexResp.statusCode}');
      }

      final index = jsonDecode(indexResp.body) as Map<String, dynamic>;
      final files = (index['extensions'] as List).cast<String>();

      final result = <SdkExtension>[];
      for (final file in files) {
        try {
          final resp = await http
              .get(Uri.parse('$_kSdkRawBase$file'))
              .timeout(const Duration(seconds: 15));
          if (resp.statusCode == 200) {
            result.add(SdkExtension.fromJson(
                jsonDecode(resp.body) as Map<String, dynamic>));
          }
        } catch (_) {}
      }
      _availableSdks = result;
      _sdkIndexError = null;
    } catch (e) {
      _sdkIndexError = 'Could not load SDK list: $e';
    }

    _loadingSdkIndex = false;
    notifyListeners();
  }

  // ── Download theme (from GitHub to app documents) ────────────────────────
  Future<void> downloadTheme(ExtensionThemeMeta meta) async {
    if (_downloading.contains(meta.id)) return;
    _downloading.add(meta.id);
    notifyListeners();

    try {
      final resp = await http
          .get(Uri.parse('$_kThemeRawBase${meta.file}'))
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');

      final json = jsonDecode(resp.body) as Map<String, dynamic>;

      // Save to documents dir with meta fields embedded
      final enriched = {
        'id': meta.id,
        'name': meta.name,
        'file': meta.file,
        'dark': meta.dark,
        'preview': meta.preview,
        ...json,
      };

      final dir = await _themesDir();
      final file = File('${dir.path}/${meta.id}.json');
      await file.writeAsString(jsonEncode(enriched));

      _installed[meta.id] = meta;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_kPrefInstalled, _installed.keys.toList());
    } catch (e) {
      debugPrint('[ExtensionsProvider] install error: $e');
    }

    _downloading.remove(meta.id);
    notifyListeners();
  }

  // ── Activate / deactivate ────────────────────────────────────────────────
  Future<void> activateTheme(String id) async {
    if (!_installed.containsKey(id)) return;
    _activeId = id;
    await _loadActiveEditorTheme(id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefActive, id);
    notifyListeners();
  }

  Future<void> deactivateTheme() async {
    _activeId = null;
    _activeEditorTheme = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefActive);
    notifyListeners();
  }

  // ── Delete ───────────────────────────────────────────────────────────────
  Future<void> deleteTheme(String id) async {
    if (_activeId == id) await deactivateTheme();

    final dir = await _themesDir();
    final file = File('${dir.path}/$id.json');
    if (await file.exists()) await file.delete();

    _installed.remove(id);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _kPrefInstalled, _installed.keys.toList());
    notifyListeners();
  }

  // ── Parse EditorTheme from saved JSON ────────────────────────────────────
  Future<void> _loadActiveEditorTheme(String id) async {
    try {
      final dir = await _themesDir();
      final file = File('${dir.path}/$id.json');
      if (!await file.exists()) return;
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _activeEditorTheme = _parseEditorTheme(json);
    } catch (e) {
      debugPrint('[ExtensionsProvider] parse error: $e');
      _activeEditorTheme = null;
    }
  }

  /// Parse a theme JSON into an [EditorTheme] — same logic as ThemeLoader._fromJson.
  static EditorTheme _parseEditorTheme(Map<String, dynamic> j,
      {double fontSize = 14}) {
    final c = (j['colors'] as Map<String, dynamic>?) ?? {};
    final blj = (j['blockLines'] as Map<String, dynamic>?) ?? {};
    final bpj = (j['bracketPair'] as Map<String, dynamic>?) ?? {};
    final idj = (j['indentDots'] as Map<String, dynamic>?) ?? {};
    final isDark = j['dark'] as bool? ?? true;

    Color h(Map<String, dynamic> m, String k, Color fb) {
      final v = m[k] as String?;
      if (v == null || v.length < 7) return fb;
      try {
        final s = v.replaceFirst('#', '');
        final argb = s.length == 6 ? 'FF$s' : s;
        return Color(int.parse(argb, radix: 16));
      } catch (_) {
        return fb;
      }
    }

    final bg = h(c, 'background', isDark ? const Color(0xFF1E1E2E) : Colors.white);
    final lnBg = h(c, 'lineNumberBackground', isDark ? const Color(0xFF181825) : const Color(0xFFF0F0F0));
    final text = h(c, 'textNormal', isDark ? const Color(0xFFCDD6F4) : Colors.black87);
    final ln = h(c, 'lineNumber', isDark ? const Color(0xFF6C7086) : Colors.grey);
    final lnCur = h(c, 'lineNumberCurrent', isDark ? Colors.white : Colors.black87);
    final cursor = h(c, 'cursor', const Color(0xFF89B4FA));
    final sel = h(c, 'selectionColor', const Color(0x3389B4FA));
    final kw = h(c, 'keyword', const Color(0xFFCBA6F7));
    final str = h(c, 'string', const Color(0xFFA6E3A1));
    final cmt = h(c, 'comment', const Color(0xFF6C7086));
    final num_ = h(c, 'number', const Color(0xFFFAB387));
    final op = h(c, 'operator', const Color(0xFF89DCEB));
    final id = h(c, 'identifier', isDark ? const Color(0xFFCDD6F4) : Colors.black87);
    final fn = h(c, 'function', const Color(0xFF89B4FA));
    final ty = h(c, 'type', const Color(0xFFF38BA8));
    final ann = h(c, 'annotation', const Color(0xFFF5C2E7));
    final blk = h(c, 'blockLine', isDark ? const Color(0xFF313244) : const Color(0xFFCCCCCC));
    final compBg = h(c, 'completionBackground', isDark ? const Color(0xFF1E1E2E) : const Color(0xFFF5F5F5));
    final ghost = h(c, 'ghostTextForeground', const Color(0xFF6C7086));
    final curLn = h(c, 'currentLineBackground', isDark ? const Color(0xFF313244) : const Color(0xFFF0F0F0));
    final srchBg = h(c, 'searchMatchBackground', isDark ? const Color(0x33F9E2AF) : const Color(0x44FFFF00));
    final srchBrd = h(c, 'searchMatchBorder', isDark ? const Color(0xFFF9E2AF) : const Color(0xFFCCCC00));
    final handle = h(c, 'selectionHandle', cursor);
    final cursorW = (c['cursorWidth'] as num?)?.toDouble() ?? 2.0;

    final blockLines = blj.isNotEmpty
        ? VsCodeThemeParser.parseBlockLineThemePublic(blj)
        : const BlockLineTheme();

    Color bphex(String k, Color fb) => h(bpj, k, fb);
    final bracketPair = BracketPairTheme(
      fillColor: bphex('fillColor', const Color(0x1A89B4FA)),
      borderColor: bphex('borderColor', const Color(0x8089B4FA)),
      borderWidth: (bpj['borderWidth'] as num?)?.toDouble() ?? 1.2,
      radius: (bpj['radius'] as num?)?.toDouble() ?? 2.0,
    );

    Color idhex(String k, Color fb) => h(idj, k, fb);
    final dotMode = (idj['mode'] as String? ?? 'indentOnly') == 'all'
        ? IndentDotMode.all
        : IndentDotMode.indentOnly;
    final indentDots = IndentDotTheme(
      visible: idj['visible'] as bool? ?? false,
      color: idhex('color', const Color(0x446C7086)),
      size: (idj['size'] as num?)?.toDouble() ?? 1.5,
      mode: dotMode,
    );

    final base = isDark
        ? QuillThemeDark.build(fontSize: fontSize)
        : QuillThemeLight.build(fontSize: fontSize);

    return base.copyWith(
      fontSize: fontSize,
      cursorWidth: cursorW,
      blockLines: blockLines,
      bracketPair: bracketPair,
      indentDots: indentDots,
      colorScheme: base.colorScheme.copyWith(
        background: bg,
        lineNumberBackground: lnBg,
        textNormal: text,
        lineNumber: ln,
        lineNumberCurrent: lnCur,
        cursor: cursor,
        selectionHandle: handle,
        selectionColor: sel,
        keyword: kw,
        string: str,
        comment: cmt,
        number: num_,
        operator_: op,
        identifier: id,
        function_: fn,
        type_: ty,
        annotation: ann,
        blockLine: blk,
        completionBackground: compBg,
        ghostTextForeground: ghost,
        currentLineBackground: curLn,
        searchMatchBackground: srchBg,
        searchMatchBorder: srchBrd,
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  static Future<Directory> _themesDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/extensions/themes');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}
