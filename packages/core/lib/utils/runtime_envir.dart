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

  // java-language-server (georgewfraser) — single-jar Java/Android LSP.
  // Installed to $PREFIX/opt/java-language-server/dist/lang.jar by the
  // Android SDK extension.  Much lighter than jdtls/kotlin-language-server
  // on Android: no OSGi, no multi-second JVM warm-up.
  static String get javaLsHome => '$usrPath/opt/java-language-server';
  static String get javaLsJar  => '$javaLsHome/dist/lang.jar';

  // Kept for forward-compatibility; no longer used for LSP launch.
  static String get jdtlsHome     => '$usrPath/opt/jdtls';
  static String get jdtlsBin      => '$usrPath/bin/jdtls';
  static String get jdtlsDataPath => '$homePath/.jdtls-data';
  static String get kotlinLsHome  => '$usrPath/opt/kotlin-language-server/server';
  static String get kotlinLsBin   => '$usrPath/bin/kotlin-language-server';

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

  // C / C++ — clangd ships with the Termux clang package
  static String get clangdBin => '$usrPath/bin/clangd';
  static String get lldbDapBin => '$usrPath/bin/lldb-vscode'; // also tries lldb-dap

  // Rust — rust-analyzer installed via rustup or pkg
  static String get cargoBin        => '$homePath/.cargo/bin/cargo';
  static String get rustAnalyzerBin => '$homePath/.cargo/bin/rust-analyzer';
  static String get rustcBin        => '$homePath/.cargo/bin/rustc';

  // Lua — lua-language-server via pkg
  static String get luaLsBin => '$usrPath/bin/lua-language-server';

  // Ruby — solargraph installed via gem
  static String get rubyBin      => '$usrPath/bin/ruby';
  static String get solargraphBin => '$usrPath/bin/solargraph';

  // PHP
  static String get phpBin => '$usrPath/bin/php';

  // Zig — zls installed via pkg or cargo
  static String get zigBin => '$usrPath/bin/zig';
  static String get zlsBin => '$usrPath/bin/zls';

  // R — r-languageserver
  static String get rBin => '$usrPath/bin/Rscript';

  // C# — csharp-ls via dotnet tool
  static String get dotnetBin   => '$homePath/.dotnet/dotnet';
  static String get csharpLsBin => '$homePath/.dotnet/tools/csharp-ls';

  // Scala — Metals via coursier
  static String get metalsBin    => '$homePath/.local/bin/metals';
  static String get coursierBin  => '$homePath/.local/bin/cs';

  // Haskell — HLS via ghcup
  static String get ghcupBin => '$homePath/.ghcup/bin/ghc';
  static String get hlsBin   => '$homePath/.ghcup/bin/haskell-language-server-wrapper';

  // Elixir — ElixirLS
  static String get elixirBin   => '$usrPath/bin/elixir';
  static String get elixirLsBin => '$homePath/.elixir-ls/language_server.sh';

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
