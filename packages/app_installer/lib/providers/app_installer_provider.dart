import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:terminal_pkg/terminal_pkg.dart';

enum InstallStatus { idle, installing, success, error }

class AppInstallerProvider extends ChangeNotifier {
  InstallStatus _installStatus = InstallStatus.idle;
  String _installOutput = '';
  String? _installError;

  // Logcat
  TerminalSession? _logcatSession;
  bool _watchingLogs = false;

  TerminalSession? get logcatSession => _logcatSession;

  // Hot reload — Flutter VM Service
  String? _vmServiceUrl;
  bool _hotReloadAvailable = false;

  InstallStatus get installStatus => _installStatus;
  String get installOutput => _installOutput;
  String? get installError => _installError;
  bool get watchingLogs => _watchingLogs;
  bool get hotReloadAvailable => _hotReloadAvailable;

  static const _kChannel = MethodChannel('com.example.fl_ide/apk_installer');

  /// Opens the system package installer UI for [apkPath].
  ///
  /// Uses a method channel → FileProvider → ACTION_INSTALL_PACKAGE intent so
  /// Android displays the standard "Do you want to install this app?" prompt.
  /// The app already holds REQUEST_INSTALL_PACKAGES permission.
  Future<void> installApk(String apkPath) async {
    if (_installStatus == InstallStatus.installing) return;

    _installStatus = InstallStatus.installing;
    _installOutput = '';
    _installError = null;
    notifyListeners();

    try {
      await _kChannel.invokeMethod<void>('installApk', {'path': apkPath});
      // The system installer UI takes over from here — we can't observe whether
      // the user ultimately accepted or rejected, so we mark as "launched".
      _installStatus = InstallStatus.success;
      _installOutput = 'System installer opened. Follow the on-screen prompt.';
    } on PlatformException catch (e) {
      _installStatus = InstallStatus.error;
      _installError = e.message ?? e.toString();
      _installOutput = _installError!;
    } catch (e) {
      _installStatus = InstallStatus.error;
      _installError = e.toString();
      _installOutput = e.toString();
    }

    notifyListeners();
  }

  /// Start watching logcat for a package
  Future<TerminalSession> startLogcat({String? packageName}) async {
    _logcatSession?.kill();

    final cmd = packageName != null
        ? 'logcat --pid=\$(pidof "$packageName") -v color'
        : 'logcat -v color';

    final session = TerminalSession(
      id: 'logcat_${DateTime.now().millisecondsSinceEpoch}',
      label: 'Logcat${packageName != null ? ' ($packageName)' : ''}',
    );

    await session.start(workingDirectory: RuntimeEnvir.homePath);
    session.writeCommand(cmd);

    _logcatSession = session;
    _watchingLogs = true;
    notifyListeners();
    return session;
  }

  void stopLogcat() {
    _logcatSession?.kill();
    _logcatSession = null;
    _watchingLogs = false;
    notifyListeners();
  }

  /// Connect to Flutter VM Service for hot reload
  Future<void> connectVmService(String host, int port) async {
    _vmServiceUrl = 'http://$host:$port';
    try {
      // Verify it's alive
      final response =
          await http.get(Uri.parse('$_vmServiceUrl/')).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        _hotReloadAvailable = true;
        notifyListeners();
      }
    } catch (_) {
      _hotReloadAvailable = false;
    }
  }

  /// Trigger hot reload via Flutter VM Service
  Future<bool> hotReload() async {
    if (!_hotReloadAvailable || _vmServiceUrl == null) return false;

    try {
      final response = await http.get(
        Uri.parse('$_vmServiceUrl/hotReload'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Trigger hot restart
  Future<bool> hotRestart() async {
    if (!_hotReloadAvailable || _vmServiceUrl == null) return false;

    try {
      final response = await http.get(
        Uri.parse('$_vmServiceUrl/hotRestart'),
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void reset() {
    _installStatus = InstallStatus.idle;
    _installOutput = '';
    _installError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    stopLogcat();
    super.dispose();
  }
}
