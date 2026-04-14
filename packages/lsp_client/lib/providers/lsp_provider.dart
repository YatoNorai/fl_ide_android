import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:quill_code/quill_code.dart';

/// LSP lifecycle states:
///   stopped  → process not configured
///   starting → starting the LSP process (handshake in progress, ~0–1s)
///   warming  → process running, waiting for first diagnostics push (~1–25s)
///   ready    → LSP has responded at least once (completions + diagnostics work)
///   error    → failed to start
enum LspStatus { stopped, starting, warming, ready, error }

class LspProvider extends ChangeNotifier {
  LspStatus _status = LspStatus.stopped;
  QuillLspConfig? _lspConfig;
  String? _error;

  LspStatus get status => _status;
  QuillLspConfig? get lspConfig => _lspConfig;
  String? get error => _error;

  /// True once the LSP process is running (warming OR ready).
  bool get isRunning => _status == LspStatus.warming || _status == LspStatus.ready;

  /// True only after the LSP has delivered its first diagnostics response.
  bool get isReady => _status == LspStatus.ready;

  /// Called by the editor when the LSP delivers its first diagnostics push.
  void markReady() {
    if (_status == LspStatus.warming) {
      _status = LspStatus.ready;
      notifyListeners();
    }
  }

  /// Build a QuillLspStdioConfig for the given file extension.
  /// The config is passed to QuillCodeEditor which manages the connection.
  /// [customPaths] overrides default binary paths per extension (key = ext, value = binary path).
  Future<void> startForExtension(String extension, String projectPath,
      {Map<String, String>? customPaths}) async {
    final cmd = _lspServerCommand(extension, customPaths: customPaths);
    if (cmd == null) {
      // Known language but binary not installed → show error so the user
      // knows why there is no LSP support, instead of silently stopping.
      const _knownLangs = {'dart', 'js', 'jsx', 'ts', 'tsx', 'py',
          'kt', 'kotlin', 'java', 'go', 'swift', 'xml'};
      if (_knownLangs.contains(extension.toLowerCase())) {
        _status = LspStatus.error;
        _error = _missingBinaryMessage(extension);
        _lspConfig = null;
        notifyListeners();
      } else {
        _status = LspStatus.stopped;
        _lspConfig = null;
        notifyListeners();
      }
      return;
    }

    _status = LspStatus.starting;
    notifyListeners();

    // JVM-based servers (Kotlin, Java, XML/LemMinX) need more time to spin up.
    // Native servers (gopls, dart, pylsp) respond in < 2 s so the default is fine.
    final isJvm = const {'kt', 'kotlin', 'java', 'xml'}.contains(extension.toLowerCase());

    // jdtls/kotlin-ls need up to 120 s on Android (cold JVM start + OSGi load);
    // LemMinX 30 s; native servers 5 s.
    final timeoutSecs = const {'kt', 'kotlin', 'java'}.contains(extension.toLowerCase())
        ? 120
        : isJvm ? 30 : 5;

    _lspConfig = QuillLspStdioConfig(
      executable: cmd.first,
      args: cmd.sublist(1),
      languageId: _languageId(extension),
      workspacePath: projectPath,
      // Pass Termux PATH so the LSP process can find node, python, etc.
      // Without this the process inherits the app's restricted environment.
      environment: _envForExtension(extension),
      initializeTimeoutSeconds: timeoutSecs,
    );
    _status = LspStatus.warming;
    notifyListeners();
  }

  void stop() {
    _lspConfig = null;
    _status = LspStatus.stopped;
    notifyListeners();
  }

  /// Called by the editor when the LSP process crashes or initialize fails.
  void setError(String message) {
    _status = LspStatus.error;
    _error = message;
    notifyListeners();
  }

  /// Start LSP using a WebSocket URL (for SSH-backed remote LSP servers).
  /// The WebSocket server is expected to speak JSON-RPC 2.0 over ws://.
  void startForSocket(String wsUrl, String extension, String projectPath) {
    _status = LspStatus.warming;
    _lspConfig = QuillLspSocketConfig(
      url: wsUrl,
      languageId: _languageId(extension),
      workspacePath: projectPath,
    );
    notifyListeners();
  }

  /// Returns the shell command to start the LSP server for [extension] on a
  /// REMOTE machine (does NOT check local file existence).
  /// Returns null if no LSP server is known for this extension.
  String? lspRemoteCommandFor(String extension) {
    switch (extension.toLowerCase()) {
      case 'dart':
        return 'dart language-server --lsp';
      case 'js':
      case 'jsx':
      case 'ts':
      case 'tsx':
        return 'typescript-language-server --stdio';
      case 'py':
        return 'pylsp';
      case 'kt':
      case 'kotlin':
        return 'kotlin-language-server';
      case 'java':
        // jdtls wrapper script installed by the Android SDK extension.
        return 'jdtls -data ~/.jdtls-data';
      case 'go':
        return 'gopls';
      case 'swift':
        return 'sourcekit-lsp';
      case 'xml':
        return 'java -jar ~/opt/lemminx/lemminx.jar';
      default:
        return null;
    }
  }

  /// Returns [executable, ...args] for the LSP server, or null if the binary
  /// is not installed or the extension is unsupported.
  List<String>? _lspServerCommand(String ext,
      {Map<String, String>? customPaths}) {
    // Check user-supplied custom path first
    final customExe = customPaths?[ext.toLowerCase()];
    if (customExe != null && customExe.isNotEmpty) {
      if (!File(customExe).existsSync()) {
        debugPrint('[LspProvider] custom binary not found: $customExe');
        return null;
      }
      // .dart.snapshot files must be run through the Dart VM, not directly.
      if (customExe.endsWith('.dart.snapshot')) {
        final dartVm = _dartVmPath;
        if (dartVm == null) {
          debugPrint('[LspProvider] dart VM not found, cannot run snapshot');
          return null;
        }
        return [dartVm, customExe, '--lsp'];
      }
      return [customExe];
    }

    switch (ext.toLowerCase()) {
      case 'dart':
        // Use the Dart VM ELF binary directly — not the shell wrapper at
        // flutter/bin/dart — so it can be exec'd without a shell interpreter.
        final dart = _dartVmPath;
        if (dart == null) {
          debugPrint('[LspProvider] dart VM not found');
          return null;
        }
        return [dart, 'language-server'];

      case 'js':
      case 'ts':
      case 'jsx':
      case 'tsx':
        // npm global shims (e.g. $PREFIX/bin/typescript-language-server) are
        // bash scripts. On Android without LD_PRELOAD=libtermux-exec.so, the
        // #!/usr/bin/env shebang fails with ENOENT because /usr/bin/env doesn't
        // exist outside Termux. We bypass the shim and run node + the real JS
        // entry file directly.
        final node = RuntimeEnvir.nodePath;
        if (!File(node).existsSync()) {
          debugPrint('[LspProvider] node not found at $node');
          return null;
        }
        final nmRoot = '${RuntimeEnvir.usrPath}/lib/node_modules/typescript-language-server';
        // Try known JS entry paths across typescript-language-server versions:
        //   v3/v4 → lib/cli.mjs
        //   v2    → out/cli.js
        //   v1    → bin/server.js
        for (final rel in const ['lib/cli.mjs', 'out/cli.js', 'bin/server.js']) {
          final jsFile = '$nmRoot/$rel';
          if (File(jsFile).existsSync()) {
            debugPrint('[LspProvider] using node $jsFile');
            return [node, jsFile, '--stdio'];
          }
        }
        // Fallback: shim exists, run via bash (works when LD_PRELOAD is set)
        final bash = RuntimeEnvir.bashPath;
        final shim = '${RuntimeEnvir.usrPath}/bin/typescript-language-server';
        if (File(bash).existsSync() && File(shim).existsSync()) {
          debugPrint('[LspProvider] falling back to bash shim: $shim');
          return [bash, shim, '--stdio'];
        }
        debugPrint('[LspProvider] typescript-language-server not found');
        return null;

      case 'py':
        final pylsp = '${RuntimeEnvir.usrPath}/bin/pylsp';
        if (!File(pylsp).existsSync()) {
          debugPrint('[LspProvider] pylsp not found');
          return null;
        }
        // pylsp is also a Python script — run via python3 directly
        final py = RuntimeEnvir.pythonPath;
        if (File(py).existsSync()) return [py, '-m', 'pylsp'];
        final bash2 = RuntimeEnvir.bashPath;
        if (File(bash2).existsSync()) return [bash2, pylsp];
        return null;

      // ── Kotlin ────────────────────────────────────────────────────────────
      case 'kt':
      case 'kotlin':
        // Prefer direct Java invocation over the bash launcher script — more
        // reliable in Termux's sandbox where exec() syscall quirks can trip up
        // shell scripts that internally call `exec java`.
        final klsLib = '${RuntimeEnvir.kotlinLsHome}/lib';
        final java3  = RuntimeEnvir.javaPath;
        if (Directory(klsLib).existsSync() && File(java3).existsSync()) {
          // kotlin-language-server main class; --stdio selects stdin/stdout transport.
          return [java3, '-cp', '$klsLib/*', 'org.javacs.kt.MainKt', '--stdio'];
        }
        // Fallback: run the bash launcher script.
        final klsScript = '${RuntimeEnvir.kotlinLsHome}/bin/kotlin-language-server';
        final klsBin    = RuntimeEnvir.kotlinLsBin;
        final ktlsBin   = File(klsScript).existsSync() ? klsScript
            : File(klsBin).existsSync() ? klsBin
            : null;
        if (ktlsBin == null) {
          debugPrint('[LspProvider] kotlin-language-server not found.'
              ' Install via Android SDK extension.');
          return null;
        }
        final bash3 = RuntimeEnvir.bashPath;
        if (!File(bash3).existsSync()) {
          debugPrint('[LspProvider] bash not found');
          return null;
        }
        return [bash3, ktlsBin, '--stdio'];

      // ── Java (Eclipse JDT Language Server) ────────────────────────────────
      case 'java':
        return _jdtlsCommand();

      // ── Go (gopls) ────────────────────────────────────────────────────────
      case 'go':
        final gopls = RuntimeEnvir.goplsBin;
        if (!File(gopls).existsSync()) {
          debugPrint('[LspProvider] gopls not found at $gopls.'
              ' Run: go install golang.org/x/tools/gopls@latest');
          return null;
        }
        return [gopls];

      // ── Swift (sourcekit-lsp) ─────────────────────────────────────────────
      case 'swift':
        final sourcekitLsp = RuntimeEnvir.sourcekitLspBin;
        if (!File(sourcekitLsp).existsSync()) {
          debugPrint('[LspProvider] sourcekit-lsp not found at $sourcekitLsp.'
              ' Install Swift via: pkg install swift');
          return null;
        }
        return [sourcekitLsp];

      // ── XML (Eclipse LemMinX) ─────────────────────────────────────────────
      case 'xml':
        final java = RuntimeEnvir.javaPath;
        if (!File(java).existsSync()) {
          debugPrint('[LspProvider] java not found at $java.'
              ' Install via: pkg install openjdk-17');
          return null;
        }
        final jar = RuntimeEnvir.lemminxJar;
        if (!File(jar).existsSync()) {
          debugPrint('[LspProvider] LemMinX jar not found at $jar.'
              ' Install via Android SDK extension.');
          return null;
        }
        // --stdio explicitly selects stdin/stdout transport (required for older
        // lsp4xml jars which default to TCP unless told otherwise).
        return [java, '-jar', jar, '--stdio'];

      default:
        return null;
    }
  }

  /// Returns a short human-readable message when a known LSP binary is missing.
  String _missingBinaryMessage(String ext) {
    switch (ext.toLowerCase()) {
      case 'java':
        return 'Java LSP (jdtls) not found.\n'
            'Install the Android SDK extension and run its install steps.';
      case 'kt':
      case 'kotlin':
        return 'Kotlin LSP not found.\n'
            'Install the Android SDK extension and run its install steps.';
      case 'go':
        return 'Go LSP (gopls) not found.\n'
            'Run: go install golang.org/x/tools/gopls@latest';
      case 'swift':
        return 'Swift LSP (sourcekit-lsp) not found.\n'
            'Run: pkg install swift';
      case 'xml':
        return 'XML LSP (LemMinX) not found.\n'
            'Install the Android SDK extension and run its install steps.';
      default:
        return 'LSP server not installed for .$ext files.';
    }
  }

  /// Constructs the full [java, ...args] command to launch jdtls by scanning
  /// the jdtls installation directory for the versioned launcher jar.
  ///
  /// Returns null and logs if jdtls is not installed or Java is missing.
  List<String>? _jdtlsCommand() {
    final bash     = RuntimeEnvir.bashPath;
    final dataDir  = RuntimeEnvir.jdtlsDataPath;
    final jdtlsHome = RuntimeEnvir.jdtlsHome;

    // 1. Custom wrapper created by the Android SDK extension install step.
    final wrapper = RuntimeEnvir.jdtlsBin;
    if (File(wrapper).existsSync()) {
      if (!File(bash).existsSync()) return null;
      Directory(dataDir).createSync(recursive: true);
      debugPrint('[LspProvider] jdtls: using custom wrapper $wrapper');
      return [bash, wrapper, '-data', dataDir];
    }

    // 2. Built-in launcher script shipped inside the jdtls distribution tarball
    //    (present in jdtls ≥ 1.x as opt/jdtls/bin/jdtls). More reliable than
    //    the raw-jar invocation because the script already sets the correct
    //    OSGi flags and JVM options for the installed version.
    final distBin = '$jdtlsHome/bin/jdtls';
    if (File(distBin).existsSync()) {
      if (!File(bash).existsSync()) return null;
      Directory(dataDir).createSync(recursive: true);
      debugPrint('[LspProvider] jdtls: using distribution launcher $distBin');
      return [bash, distBin, '-data', dataDir];
    }

    // 3. Last resort: invoke the launcher JAR directly with Java.
    final pluginsDir = Directory('$jdtlsHome/plugins');
    if (!pluginsDir.existsSync()) {
      debugPrint('[LspProvider] jdtls not found at $jdtlsHome.'
          ' Install via Android SDK extension.');
      return null;
    }

    final jars = pluginsDir
        .listSync()
        .whereType<File>()
        .where((f) =>
            f.path.contains('org.eclipse.equinox.launcher_') &&
            f.path.endsWith('.jar'))
        .map((f) => f.path)
        .toList()
      ..sort();

    if (jars.isEmpty) {
      debugPrint('[LspProvider] jdtls launcher jar not found in $pluginsDir');
      return null;
    }
    final launcherJar = jars.last;

    final java = RuntimeEnvir.javaPath;
    if (!File(java).existsSync()) {
      debugPrint('[LspProvider] java not found at $java. Install openjdk-17.');
      return null;
    }

    // Prefer ARM64-specific config dir; fall back to generic Linux.
    String configDir = '$jdtlsHome/config_linux_arm64';
    if (!Directory(configDir).existsSync()) configDir = '$jdtlsHome/config_linux';
    if (!Directory(configDir).existsSync()) {
      debugPrint('[LspProvider] jdtls config directory not found in $jdtlsHome');
      return null;
    }

    Directory(dataDir).createSync(recursive: true);
    debugPrint('[LspProvider] jdtls: using raw jar $launcherJar');

    return [
      java,
      '-Declipse.application=org.eclipse.jdt.ls.core.id1',
      '-Dosgi.bundles.defaultStartLevel=4',
      '-Declipse.product=org.eclipse.jdt.ls.core.product',
      '-Dlog.level=ERROR',
      '--add-modules=ALL-SYSTEM',
      '--add-opens', 'java.base/java.util=ALL-UNNAMED',
      '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
      '-jar', launcherJar,
      '-configuration', configDir,
      '-data', dataDir,
    ];
  }

  /// Path to the Dart VM binary (the ELF executable, not the shell wrapper).
  String? get _dartVmPath {
    final path = '${RuntimeEnvir.flutterPath}/bin/cache/dart-sdk/bin/dart';
    return File(path).existsSync() ? path : null;
  }

  /// Returns the environment map for a given file extension.
  /// Java and Kotlin LSP servers need JAVA_HOME so their launcher scripts can
  /// locate the JVM. We only inject it when we can confirm the path is valid;
  /// if the path is unknown/wrong the launcher script dies with
  /// "JAVA_HOME is set to an invalid directory", so it is safer to omit it
  /// and let the script fall back to `java` from PATH.
  Map<String, String> _envForExtension(String ext) {
    final base = RuntimeEnvir.baseEnv;
    switch (ext.toLowerCase()) {
      case 'kt':
      case 'kotlin':
        // kotlin-language-server needs JAVA_HOME for the JVM.
        // KOTLIN_LS_HOME helps the launcher find its lib/ dir if $0-resolution
        // fails inside the Termux sandbox (process started without a tty).
        // JAVA_TOOL_OPTIONS caps heap to avoid OOM on Android devices with
        // limited RAM — kotlin-language-server defaults to 512 MB which kills
        // the process on low-memory devices.
        final jHome = RuntimeEnvir.javaHome;
        final env = <String, String>{...base};
        if (jHome.isNotEmpty) env['JAVA_HOME'] = jHome;
        env['KOTLIN_LS_HOME'] = RuntimeEnvir.kotlinLsHome;
        env['JAVA_TOOL_OPTIONS'] = '-Xmx200m -Xms32m';
        return env;
      case 'java':
        final jHome = RuntimeEnvir.javaHome;
        final javaEnv = jHome.isNotEmpty ? <String, String>{...base, 'JAVA_HOME': jHome} : <String, String>{...base};
        // Cap jdtls heap to avoid OOM on Android.
        javaEnv['JAVA_TOOL_OPTIONS'] = '-Xmx256m -Xms32m';
        return javaEnv;
      default:
        return base;
    }
  }

  String _languageId(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':    return 'dart';
      case 'js':      return 'javascript';
      case 'jsx':     return 'javascriptreact';
      case 'ts':      return 'typescript';
      case 'tsx':     return 'typescriptreact';
      case 'py':      return 'python';
      case 'kt':
      case 'kotlin':  return 'kotlin';
      case 'java':    return 'java';
      case 'go':      return 'go';
      case 'swift':   return 'swift';
      case 'xml':     return 'xml';
      default:        return ext;
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
