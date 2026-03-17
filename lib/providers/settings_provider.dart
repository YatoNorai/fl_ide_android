import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SettingsPage {
  main,
  general,
  editor,
  fileExplorer,
  terminal,
  runDebug,
  extensions,
  about,
}

class SettingsProvider extends ChangeNotifier {
  static const String _keyFollowSystem = 'followSystemTheme';
  static const String _keyUseDarkMode = 'useDarkMode';
  static const String _keyUseAmoled = 'useAmoled';
  static const String _keyUseDynamicColors = 'useDynamicColors';

  bool _followSystemTheme = true;
  bool _useDarkMode = false;
  bool _useAmoled = false;
  bool _useDynamicColors = false;

  SettingsPage _currentPage = SettingsPage.main;

  bool get followSystemTheme => _followSystemTheme;
  bool get useDarkMode => _useDarkMode;
  bool get useAmoled => _useAmoled;
  bool get useDynamicColors => _useDynamicColors;
  SettingsPage get currentPage => _currentPage;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _followSystemTheme = prefs.getBool(_keyFollowSystem) ?? true;
    _useDarkMode = prefs.getBool(_keyUseDarkMode) ?? false;
    _useAmoled = prefs.getBool(_keyUseAmoled) ?? false;
    _useDynamicColors = prefs.getBool(_keyUseDynamicColors) ?? false;
    notifyListeners();
  }

  void navigateToPage(SettingsPage page) {
    _currentPage = page;
    notifyListeners();
  }

  void goBack() {
    _currentPage = SettingsPage.main;
    notifyListeners();
  }

  Future<void> setFollowSystemTheme(bool val) async {
    _followSystemTheme = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyFollowSystem, val);
    notifyListeners();
  }

  Future<void> setUseDarkMode(bool val) async {
    _useDarkMode = val;
    if (val) _followSystemTheme = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseDarkMode, val);
    if (val) await prefs.setBool(_keyFollowSystem, false);
    notifyListeners();
  }

  Future<void> setUseAmoled(bool val) async {
    _useAmoled = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseAmoled, val);
    notifyListeners();
  }

  Future<void> setUseDynamicColors(bool val) async {
    _useDynamicColors = val;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyUseDynamicColors, val);
    notifyListeners();
  }
}
