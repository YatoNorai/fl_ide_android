import 'dart:io';

/// Paths and environment for the rootfs (inspired by termare's RuntimeEnvir)
class RuntimeEnvir {
  static const String packageName = 'com.termux';

  // Android data dir: /data/data/com.termux/files
  static String get filesPath => '/data/data/$packageName/files';
  static String get usrPath => '$filesPath/usr';
  static String get homePath => '$filesPath/home';

  // Shells
  static String get bashPath => '$usrPath/bin/bash';
  static String get zshPath => '$usrPath/bin/zsh';

  // SDK paths inside rootfs
  static String get flutterPath => '$usrPath/flutter';
  static String get androidSdkPath => '$usrPath/android-sdk';
  static String get nodePath => '$usrPath/bin/node';
  static String get npmPath => '$usrPath/bin/npm';
  static String get pythonPath => '$usrPath/bin/python3';

  // Projects dir
  static String get projectsPath => '$homePath/projects';

  /// Base environment variables, same approach as termare
  static Map<String, String> get baseEnv => {
        'HOME': homePath,
        'TERM': 'xterm-256color',
        'TERMUX_PREFIX': usrPath,
        'PATH':
            '$usrPath/bin:$usrPath/bin/applets:${Platform.environment['PATH'] ?? ''}',
        'LD_PRELOAD': '$usrPath/lib/libtermux-exec.so',
        'LANG': 'en_US.UTF-8',
        'ANDROID_HOME': androidSdkPath,
        'FLUTTER_ROOT': flutterPath,
        'PUB_CACHE': '$homePath/.pub-cache',
      };

  /// Check if rootfs bootstrap is present
  static bool get isBootstrapped => Directory(usrPath).existsSync();

  /// Check if a specific binary is available
  static bool isBinaryAvailable(String binName) =>
      File('$usrPath/bin/$binName').existsSync();
}
