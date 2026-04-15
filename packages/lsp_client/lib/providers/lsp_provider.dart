import 'dart:async';
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

  // ── Project-wide diagnostics ───────────────────────────────────────────────
  // Populated by [attachClient] via listenAllDiagnostics — captures every
  // publishDiagnostics notification the server sends, including for files that
  // are not currently open in the editor.
  final Map<String, List<LspDiagnostic>> _projectDiagnostics = {};
  StreamSubscription<void>? _allDiagSub;

  /// URIs that currently have an active LspBinding in the editor (i.e. the
  /// editor has called didOpen for them and hasn't yet called didClose).
  /// Used to distinguish genuine "file is clean" empty pushes from
  /// "server cleared on didClose" empty pushes.
  final _activelyOpenUris = <String>{};

  LspStatus get status => _status;
  QuillLspConfig? get lspConfig => _lspConfig;
  String? get error => _error;

  /// All diagnostics received from the LSP server since it started, keyed by
  /// file URI (e.g. `file:///path/to/lib/main.dart`).  Includes files that are
  /// not open in the editor — use this for the project-wide Problems panel.
  Map<String, List<LspDiagnostic>> get projectDiagnostics =>
      Map.unmodifiable(_projectDiagnostics);

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

    // JVM-based servers need more time to spin up.
    // Native servers (gopls, dart, pylsp) respond in < 2 s so the default is fine.
    final ext = extension.toLowerCase();

    // kotlin-language-server on Termux/Android: ~30–60 s cold start (JVM + Kotlin
    // compiler analysis).  java-language-server: ~10–15 s (no OSGi).
    // LemMinX: ~20–30 s.  Native servers: 5 s.
    final timeoutSecs = switch (ext) {
      'kt' || 'kotlin' => 120, // kotlin-ls: JVM cold-start + Kotlin compiler init on Android
      'java'           => 60,  // java-language-server
      'xml'            => 30,  // LemMinX
      _                => 5,
    };

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
    detachClient();
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

  /// Notify [LspProvider] that the editor has called textDocument/didOpen for
  /// [uri].  Call this immediately after [QuillCodeController.attachLsp].
  void notifyFileOpenedOnLsp(String uri) => _activelyOpenUris.add(uri);

  /// Notify [LspProvider] that the editor has called textDocument/didClose for
  /// [uri].  Call this when switching away from a tab or closing a tab.
  void notifyFileClosedOnLsp(String uri) => _activelyOpenUris.remove(uri);

  /// Wire the successfully-started [client] so we can track project-wide
  /// diagnostics, then trigger a workspace scan so the server analyses every
  /// project file — not just the one currently open in the editor.
  void attachClient(LspClient client) {
    _allDiagSub?.cancel();
    _projectDiagnostics.clear();
    _activelyOpenUris.clear();
    _allDiagSub = client.listenAllDiagnostics((uri, diags) {
      if (diags.isNotEmpty) {
        // Server found issues — store/update.
        _projectDiagnostics[uri] = diags;
        notifyListeners();
      } else if (_activelyOpenUris.contains(uri)) {
        // File is actively open in the editor AND server says it's clean
        // (user fixed the errors).  Safe to remove the entry.
        _projectDiagnostics.remove(uri);
        notifyListeners();
      }
      // else: empty push triggered by didClose (tab switch / file close).
      // Preserve the last known diagnostics so the Problems panel still
      // shows issues for files that are not currently open in the editor.

      // Any publishDiagnostics notification (including empty "clean file"
      // pushes) means the server has finished its initial analysis and is
      // fully functional.  Mark ready here so the loading indicator clears
      // without having to wait for the workspace_screen.dart fallback timer.
      // This is especially important for slow JVM servers (kotlin-ls) where
      // the first diagnostic push can arrive long after initialization.
      markReady();
    });
    // Fire-and-forget: open all project files so the server pushes diagnostics
    // for every file, giving us a real project-wide Problems view.
    _scanWorkspace(client);
  }

  /// Walk the workspace directory and send textDocument/didOpen for every file
  /// matching the current LSP language.  The server then analyses each file
  /// and pushes publishDiagnostics notifications that end up in
  /// [_projectDiagnostics] via [listenAllDiagnostics].
  ///
  /// Files are sent in small batches with a short pause between each batch so
  /// we don't flood the server (important for JVM-based servers like jdtls).
  Future<void> _scanWorkspace(LspClient client) async {
    final cfg = _lspConfig;
    if (cfg == null) return;

    final exts = _extensionsForLanguageId(cfg.languageId);
    if (exts.isEmpty) return;

    final root = Directory(cfg.workspacePath);
    if (!root.existsSync()) return;

    // Directories that should never be scanned (generated/build artefacts or
    // platform sub-trees irrelevant to the active language).
    // Note: 'android' is excluded only for Flutter projects where Java/Kotlin
    // are not the primary language — for pure Android projects the entire
    // workspace IS the Android project and nothing should be excluded here.
    final isAndroidLang = const {'java', 'kotlin'}.contains(cfg.languageId);
    final skip = {
      'build', '.dart_tool', '.git', '.gradle', '.idea', '.kotlin',
      'node_modules', '.pub-cache', '.pub', '__pycache__',
      // Skip platform sub-dirs only when editing Flutter/JS/Python projects.
      if (!isAndroidLang) ...{'android', 'ios', 'windows', 'macos', 'linux', 'web'},
    };

    final files = <File>[];
    const maxFiles = 400;

    void collect(Directory dir) {
      if (files.length >= maxFiles) return;
      try {
        for (final entity in dir.listSync()) {
          if (files.length >= maxFiles) return;
          if (entity is Directory) {
            final name = entity.path.split('/').last.split('\\').last;
            if (!skip.contains(name)) collect(entity);
          } else if (entity is File) {
            final name = entity.path.split('/').last.split('\\').last;
            final dot = name.lastIndexOf('.');
            if (dot != -1 && exts.contains(name.substring(dot + 1).toLowerCase())) {
              files.add(entity);
            }
          }
        }
      } catch (_) {}
    }

    collect(root);

    // Send didOpen in batches of 10 with a small gap between batches so we
    // don't stall a JVM server that's still warming up.
    const batchSize = 10;
    const batchDelay = Duration(milliseconds: 200);

    for (var i = 0; i < files.length; i++) {
      if (!client.isReady) break;
      try {
        final path    = files[i].path;
        final uri     = Uri.file(path).toString();
        final content = await files[i].readAsString();
        await client.didOpen(
          uri:        uri,
          languageId: cfg.languageId,
          text:       content,
          version:    1,
        );
      } catch (_) {}

      // Pause between batches — avoids flooding slow JVM servers.
      if ((i + 1) % batchSize == 0) {
        await Future<void>.delayed(batchDelay);
      }
    }
  }

  /// Maps a languageId back to the set of file extensions this LSP handles.
  static Set<String> _extensionsForLanguageId(String langId) {
    switch (langId) {
      case 'dart':                return {'dart'};
      case 'kotlin':              return {'kt', 'kts'};
      case 'java':                return {'java'};
      case 'python':              return {'py'};
      case 'javascript':
      case 'javascriptreact':     return {'js', 'jsx', 'mjs'};
      case 'typescript':
      case 'typescriptreact':     return {'ts', 'tsx'};
      case 'go':                  return {'go'};
      case 'swift':               return {'swift'};
      case 'xml':                 return {'xml'};
      default:                    return {};
    }
  }

  /// Detach the current client's global diagnostics listener and clear the
  /// project-wide map.  Called when the LSP is stopped or the client is shut down.
  void detachClient() {
    _allDiagSub?.cancel();
    _allDiagSub = null;
    _projectDiagnostics.clear();
    _activelyOpenUris.clear();
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
        return 'java -jar ${RuntimeEnvir.javaLsJar}';
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
        // --suppress-analytics: skip analytics ping that adds ~200 ms cold start.
        // --protocol=lsp: explicit LSP mode (default but avoids version detection).
        // --client-id / --client-version: lets the server adjust behaviour for
        // known clients and avoids generic "unknown" warnings in server logs.
        return [dart, 'language-server',
                '--suppress-analytics',
                '--client-id=fl_ide',
                '--client-version=1.0'];

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

      // ── Kotlin (kotlin-language-server, fallback: java-language-server) ──────
      // kotlin-language-server is a shell script installed at
      //   $PREFIX/opt/kotlin-language-server/server/bin/kotlin-language-server
      // (and optionally symlinked to $PREFIX/bin/kotlin-language-server).
      // We run it via bash because Termux shell scripts need either a login
      // shell or LD_PRELOAD=libtermux-exec.so to exec /usr/bin/env correctly.
      // Falls back to java-language-server if kotlin-ls is not installed.
      case 'kt':
      case 'kotlin':
        return _kotlinLsCommand() ?? _javaLsCommand();

      // ── Java (java-language-server by georgewfraser) ─────────────────────────
      // Single self-contained jar, no OSGi, starts in ~10 s on Android.
      case 'java':
        return _javaLsCommand();

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
        // lsp4xml/LemMinX uses stdio by default — no extra flags needed.
        // The --stdio flag does NOT exist in lsp4xml 0.3.0 and causes a crash.
        return [java, '-jar', jar];

      default:
        return null;
    }
  }

  /// Returns a short human-readable message when a known LSP binary is missing.
  String _missingBinaryMessage(String ext) {
    switch (ext.toLowerCase()) {
      case 'java':
        return 'Java LSP (java-language-server) not found.\n'
            'Install the Android SDK extension and run its install steps.';
      case 'kt':
      case 'kotlin':
        return 'Kotlin LSP (kotlin-language-server) not found.\n'
            'Install via: pkg install kotlin-language-server\n'
            'or reinstall the Android SDK extension.';
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

  /// Launches kotlin-language-server by invoking the JVM directly.
  ///
  /// The Gradle-generated startup script contains
  ///   DEFAULT_JVM_OPTS='"-Xmx2g" "-Xss8m" "-XX:+UseG1GC"'
  /// which appears on the command line AFTER any JAVA_TOOL_OPTIONS we set.
  /// The JVM honours the LAST -Xmx, so the script's -Xmx2g always wins —
  /// requesting 2 GB on Android → JVM fails to start → LSP never initialises.
  ///
  /// Fix: bypass the script entirely and run `java -classpath <all JARs>
  /// org.javacs.kt.MainKt` directly, passing our own -Xmx up front.
  ///
  /// Returns null when the JVM or the server JARs are not found; the caller
  /// then falls back to [_javaLsCommand].
  List<String>? _kotlinLsCommand() {
    final java = RuntimeEnvir.javaPath;
    if (!File(java).existsSync()) {
      debugPrint('[LspProvider] java not found at $java — cannot launch kotlin-ls');
      return null;
    }

    // kotlin-language-server ships all its JARs under server/lib/.
    final libDir = Directory('${RuntimeEnvir.kotlinLsHome}/lib');
    if (!libDir.existsSync()) {
      debugPrint('[LspProvider] kotlin-ls lib dir not found at ${libDir.path}');
      return null;
    }

    final jars = libDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jar'))
        .map((f) => f.path)
        .toList();

    if (jars.isEmpty) {
      debugPrint('[LspProvider] no JARs found in ${libDir.path}');
      return null;
    }

    final classpath = jars.join(':');
    debugPrint('[LspProvider] kotlin-language-server: direct JVM with ${jars.length} JARs');
    return [
      java,
      '-Xmx384m', '-Xms64m',
      '-Xss4m',
      '-Dfile.encoding=UTF-8',
      '-classpath', classpath,
      'org.javacs.kt.MainKt',
    ];
  }

  /// Launches java-language-server (georgewfraser/java-language-server).
  ///
  /// The server ships as a single self-contained jar at
  /// [RuntimeEnvir.javaLsJar].  It speaks LSP over stdin/stdout with no
  /// extra flags required, starts in under 10 s on Android (no OSGi layer),
  /// and handles both .java and .kt files in Android projects.
  ///
  /// Returns null when the jar or the JVM binary is missing.
  List<String>? _javaLsCommand() {
    final java = RuntimeEnvir.javaPath;
    if (!File(java).existsSync()) {
      debugPrint('[LspProvider] java not found at $java.'
          ' Install via: pkg install openjdk-17');
      return null;
    }
    final jar = RuntimeEnvir.javaLsJar;
    if (!File(jar).existsSync()) {
      debugPrint('[LspProvider] java-language-server jar not found at $jar.'
          ' Install via Android SDK extension.');
      return null;
    }
    debugPrint('[LspProvider] java-language-server: $java -jar $jar');
    return [java, '-jar', jar];
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
      // kotlin-language-server is launched directly via `java -classpath …` so
      // JVM flags (-Xmx etc.) are passed on the command line, not via
      // JAVA_TOOL_OPTIONS. JAVA_HOME is still needed so the runtime can locate
      // its standard libraries.
      case 'kt':
      case 'kotlin':
        final ktJHome = RuntimeEnvir.javaHome;
        final ktEnv = <String, String>{...base};
        if (ktJHome.isNotEmpty) ktEnv['JAVA_HOME'] = ktJHome;
        // Do NOT set JAVA_TOOL_OPTIONS — flags are passed directly in the
        // command, so the env var is redundant and could conflict.
        return ktEnv;

      // java-language-server — lighter, ~128 MB is sufficient.
      case 'java':
        final jHome = RuntimeEnvir.javaHome;
        final env = <String, String>{...base};
        if (jHome.isNotEmpty) env['JAVA_HOME'] = jHome;
        env['JAVA_TOOL_OPTIONS'] = '-Xmx256m -Xms32m';
        return env;
      case 'xml':
        // LemMinX/lsp4xml is also JVM-based — cap heap to avoid OOM.
        final xmlJHome = RuntimeEnvir.javaHome;
        final xmlEnv = xmlJHome.isNotEmpty
            ? <String, String>{...base, 'JAVA_HOME': xmlJHome}
            : <String, String>{...base};
        xmlEnv['JAVA_TOOL_OPTIONS'] = '-Xmx128m -Xms16m';
        return xmlEnv;
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
    _allDiagSub?.cancel();
    stop();
    super.dispose();
  }
}
