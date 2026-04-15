import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/sdk_definition.dart';

class SdkManagerProvider extends ChangeNotifier {
  final Map<SdkType, bool> _installed = {};
  final Map<SdkType, String?> _versions = {};
  final Map<SdkType, bool> _loading = {};

  bool isInstalled(SdkType type) => _installed[type] ?? false;
  String? version(SdkType type) => _versions[type];
  bool isLoading(SdkType type) => _loading[type] ?? false;

  List<SdkType> get installedSdks =>
      SdkType.values.where((t) => isInstalled(t)).toList();

  Future<void> initialize() async {
    await _loadFromPrefs();
    await checkAll();
  }

  Future<void> checkAll() async {
    for (final def in SdkDefinition.all) {
      await _checkSdk(def.type);
    }
  }

  Future<void> _checkSdk(SdkType type) async {
    final def = SdkDefinition.forType(type);
    final binaryPath = '${RuntimeEnvir.usrPath}/bin/${def.verifyBinary}';
    final exists = File(binaryPath).existsSync();
    _installed[type] = exists;
    notifyListeners();
  }

  /// Returns the shell command to install [type].
  ///
  /// The script is wrapped with `set -e` + a `trap … ERR` that automatically
  /// runs the SDK's [SdkDefinition.cleanupScript] on failure so that any
  /// partially-installed files are removed before the user retries.
  String installCommand(SdkType type) {
    final def = SdkDefinition.forType(type);
    final cleanup = def.cleanupScript.trim();
    if (cleanup.isEmpty) return def.installScript;
    return '''
set -e
_sdk_install_cleanup() {
  echo ""
  echo "❌ Instalação falhou. Removendo arquivos parciais com rm -rf..."
$cleanup
  echo "🗑️  Limpeza concluída. Você pode tentar novamente."
}
trap _sdk_install_cleanup ERR

${def.installScript}
''';
  }

  void markInstalled(SdkType type, {String? version}) {
    _installed[type] = true;
    _versions[type] = version;
    _loading[type] = false;
    _saveToPrefs();
    notifyListeners();
  }

  void setLoading(SdkType type, bool loading) {
    _loading[type] = loading;
    notifyListeners();
  }

  Future<void> _loadFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final type in SdkType.values) {
      _installed[type] = prefs.getBool('sdk_${type.name}') ?? false;
      _versions[type] = prefs.getString('sdk_ver_${type.name}');
    }
    notifyListeners();
  }

  Future<void> _saveToPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final type in SdkType.values) {
      await prefs.setBool('sdk_${type.name}', _installed[type] ?? false);
      if (_versions[type] != null) {
        await prefs.setString('sdk_ver_${type.name}', _versions[type]!);
      }
    }
  }
}
