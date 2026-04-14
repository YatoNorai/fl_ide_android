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
  static String get flutterPath => '$usrPath/opt/flutter';
  // termux-android-sdk (mumumusuc) installs to $PREFIX/opt/android-sdk
  static String get androidSdkPath => '$usrPath/opt/android-sdk';
  static String get nodePath => '$usrPath/bin/node';
  static String get npmPath => '$usrPath/bin/npm';
  static String get pythonPath => '$usrPath/bin/python3';

  // Java
  static String get javaPath    => '$usrPath/bin/java';

  /// JAVA_HOME for the Termux OpenJDK installation.
  /// Checks known Termux paths in order; returns the first that contains
  /// a `bin/java` executable. Returns empty string if none is found.
  static String get javaHome {
    final candidates = [
      '$usrPath/lib/jvm/java-17-openjdk',
      '$usrPath/lib/jvm/openjdk-17',
      '$usrPath/lib/jvm/java-21-openjdk',
      '$usrPath/lib/jvm/java-11-openjdk',
      '$usrPath/opt/java/17',
      '$usrPath/opt/openjdk',
    ];
    for (final path in candidates) {
      if (File('$path/bin/java').existsSync()) return path;
    }
    return ''; // not found — callers should skip JAVA_HOME in this case
  }

  // Eclipse JDT Language Server (Java LSP)
  static String get jdtlsHome   => '$usrPath/opt/jdtls';
  /// Launcher wrapper created by the Android SDK extension install step.
  static String get jdtlsBin    => '$usrPath/bin/jdtls';
  /// Per-user workspace storage required by jdtls (-data flag).
  static String get jdtlsDataPath => '$homePath/.jdtls-data';

  // Kotlin Language Server
  static String get kotlinLsHome => '$usrPath/opt/kotlin-language-server/server';
  static String get kotlinLsBin  => '$usrPath/bin/kotlin-language-server';

  // Go
  /// GOPATH root — where `go install` places binaries (go/bin/).
  static String get goPath    => '$homePath/go';
  static String get goplsBin  => '$goPath/bin/gopls';
  static String get dlvBin    => '$goPath/bin/dlv';

  // Swift — sourcekit-lsp ships with the Termux Swift package
  static String get sourcekitLspBin => '$usrPath/bin/sourcekit-lsp';

  // Eclipse LemMinX — XML Language Server (standalone uber jar)
  // Installed by the Android SDK extension at $PREFIX/opt/lemminx/lemminx.jar
  static String get lemminxJar => '$usrPath/opt/lemminx/lemminx.jar';

  // Projects dir
  static String get projectsPath => '$homePath/projects';

  /// Base environment variables, same approach as termare.
  /// LD_PRELOAD is only set when libtermux-exec.so is present and readable.
  /// If set unconditionally and the file is missing/unreadable, the dynamic
  /// linker returns EACCES before execvp can replace the child process, which
  /// leaves the forked child alive with inherited binder FDs → libbinder abort
  /// (SIGABRT / exit code -6).
  static Map<String, String> get baseEnv {
    final env = <String, String>{
      'HOME': homePath,
      'TERM': 'xterm-256color',
      'TERMUX_PREFIX': usrPath,
      'PATH':
          '$usrPath/bin:$usrPath/bin/applets:${Platform.environment['PATH'] ?? ''}',
      'LANG': 'en_US.UTF-8',
      'ANDROID_HOME': androidSdkPath,
      'FLUTTER_ROOT': flutterPath,
      'PUB_CACHE': '$homePath/.pub-cache',
      // Gradle/JVM performance: avoid 30-45s daemon startup overhead by
      // pre-configuring the heap and disabling unnecessary features.
      'GRADLE_OPTS': '-Xmx512m -Xms128m -Dfile.encoding=UTF-8',
      'JAVA_OPTS':   '-Xmx512m -Xms128m -Dfile.encoding=UTF-8',
    };

    // Only preload the exec interceptor when the .so is actually on disk.
    final execSo = '$usrPath/lib/libtermux-exec.so';
    if (File(execSo).existsSync()) {
      env['LD_PRELOAD'] = execSo;
    }

    return env;
  }

  /// Check if rootfs bootstrap is present
  static bool get isBootstrapped => Directory(usrPath).existsSync();

  /// Check if a specific binary is available
  static bool isBinaryAvailable(String binName) =>
      File('$usrPath/bin/$binName').existsSync();
}
