import '../utils/runtime_envir.dart';

/// Per-SDK project configuration (new project cmd, entry file, sync, etc.)
/// Lives in JSON → `sdk_config` key.
class SdkConfig {
  /// Command to create a new project. `$name` is replaced with project name.
  final String newProjectCmd;

  /// Default file to open when a project is loaded (relative to project root).
  final String defaultEntryFile;

  /// File extensions used by this SDK (for syntax highlighting).
  final List<String> fileExtensions;

  /// Command to install/sync dependencies (e.g. `flutter pub get`).
  /// Empty string = no sync step.
  final String syncCommand;

  /// File whose presence triggers the sync banner (e.g. `pubspec.yaml`).
  /// Empty string = no auto-sync suggestion.
  final String syncTriggerFile;

  /// Command used to format source files (e.g. `dart format`).
  /// Empty string = no format step.
  final String formatCommand;

  const SdkConfig({
    required this.newProjectCmd,
    required this.defaultEntryFile,
    required this.fileExtensions,
    this.syncCommand = '',
    this.syncTriggerFile = '',
    this.formatCommand = '',
  });

  factory SdkConfig.fromJson(Map<String, dynamic> j) => SdkConfig(
        newProjectCmd: (j['new_project_cmd'] as String?) ?? '',
        defaultEntryFile: (j['default_entry_file'] as String?) ?? '',
        fileExtensions:
            ((j['file_extensions'] as List?) ?? []).cast<String>(),
        syncCommand: (j['sync_command'] as String?) ?? '',
        syncTriggerFile: (j['sync_trigger_file'] as String?) ?? '',
        formatCommand: (j['format_command'] as String?) ?? '',
      );
}

/// DAP (Debug Adapter Protocol) adapter configuration for an SDK.
/// Lives in JSON → `dap_config` key.
class DapConfig {
  /// Path to the DAP adapter binary.
  /// Supports `$FLUTTER_ROOT`, `$PREFIX`, `$HOME` placeholders.
  final String adapterBinary;

  /// Arguments passed to the adapter process (e.g. `["debug_adapter"]`).
  final List<String> adapterArgs;

  /// `adapterID` sent in the DAP `initialize` request (e.g. `"dart"`).
  final String adapterId;

  /// `program` field sent in the DAP `launch` request
  /// (relative to project root, e.g. `"lib/main.dart"`).
  final String launchProgram;

  /// Shell command to enumerate available devices.
  /// Output must be JSON compatible with `flutter devices --machine`.
  /// Empty string = skip device discovery.
  final String devicesCommand;

  /// Substrings in DAP `output` events that indicate the build has finished
  /// and the app is running (clears the "building" progress indicator).
  final List<String> buildDoneStrings;

  /// Maps platform setting name → device ID passed in DAP `launch`.
  /// e.g. `{"android": "android", "web": "web-server", "linux": "linux"}`.
  final Map<String, String> platformDeviceMap;

  /// Platform name that activates the web preview overlay.
  /// Empty string = no web preview.
  final String webPlatform;

  /// Extra `toolArgs` injected into DAP `launch` when the web platform is
  /// selected (e.g. `["-d", "web-server", "--web-port", "5050", ...]`).
  final List<String> webServerArgs;

  /// When true, the adapter starts a TCP DAP server instead of stdio.
  /// The IDE connects via socket after reading the port from the adapter's
  /// stderr (pattern: `DAP server listening at: HOST:PORT`).
  final bool tcpMode;

  const DapConfig({
    required this.adapterBinary,
    required this.adapterArgs,
    required this.adapterId,
    required this.launchProgram,
    this.devicesCommand = '',
    this.buildDoneStrings = const [],
    this.platformDeviceMap = const {},
    this.webPlatform = '',
    this.webServerArgs = const [],
    this.tcpMode = false,
  });

  /// Returns true when this config has a valid adapter binary.
  bool get hasDap => adapterBinary.isNotEmpty;

  /// Resolves `$FLUTTER_ROOT`, `$PREFIX`, `$HOME` in [adapterBinary].
  String get resolvedBinary => adapterBinary
      .replaceAll(r'$FLUTTER_ROOT', RuntimeEnvir.flutterPath)
      .replaceAll(r'$PREFIX', RuntimeEnvir.usrPath)
      .replaceAll(r'$HOME', RuntimeEnvir.homePath);

  /// Resolves env var placeholders in [devicesCommand].
  String get resolvedDevicesCommand => devicesCommand
      .replaceAll(r'$FLUTTER_ROOT', RuntimeEnvir.flutterPath)
      .replaceAll(r'$PREFIX', RuntimeEnvir.usrPath)
      .replaceAll(r'$HOME', RuntimeEnvir.homePath);

  /// Returns the device ID for [platform] from [platformDeviceMap],
  /// falling back to the platform name itself.
  String deviceIdFor(String platform) =>
      platformDeviceMap[platform] ?? platform;

  factory DapConfig.fromJson(Map<String, dynamic> j) => DapConfig(
        adapterBinary: (j['adapter_binary'] as String?) ?? '',
        adapterArgs:
            ((j['adapter_args'] as List?) ?? []).cast<String>(),
        adapterId: (j['adapter_id'] as String?) ?? '',
        launchProgram: (j['launch_program'] as String?) ?? '',
        devicesCommand: (j['devices_command'] as String?) ?? '',
        buildDoneStrings:
            ((j['build_done_strings'] as List?) ?? []).cast<String>(),
        platformDeviceMap:
            ((j['platform_device_map'] as Map?) ?? {}).cast<String, String>(),
        webPlatform: (j['web_platform'] as String?) ?? '',
        webServerArgs:
            ((j['web_server_args'] as List?) ?? []).cast<String>(),
        tcpMode: (j['tcp_mode'] as bool?) ?? false,
      );

  static const empty = DapConfig(
    adapterBinary: '',
    adapterArgs: [],
    adapterId: '',
    launchProgram: '',
    tcpMode: false,
  );
}
