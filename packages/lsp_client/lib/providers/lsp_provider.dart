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

  LspProvider() {
    MemoryPressureService.instance.addModerateListener(_onMemoryPressure);
  }

  // ── Workspace scan cancellation ───────────────────────────────────────────
  // Set to true to abort an in-progress _scanWorkspace loop.  Reset to false
  // at the top of each new scan so subsequent calls start fresh.
  bool _scanCancelled = false;

  // ── Project-wide diagnostics ───────────────────────────────────────────────
  // Populated by [attachClient] via listenAllDiagnostics — captures every
  // publishDiagnostics notification the server sends, including for files that
  // are not currently open in the editor.
  final Map<String, List<LspDiagnostic>> _projectDiagnostics = {};
  StreamSubscription<void>? _allDiagSub;
  // Debounce: coalesces rapid publishDiagnostics bursts (workspace scan can
  // send up to 400 files) into one rebuild per 100 ms window.
  Timer? _diagDebounceTimer;

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
      const _knownLangs = {
        'dart', 'js', 'jsx', 'ts', 'tsx', 'py',
        'kt', 'kotlin', 'java', 'go', 'swift', 'xml',
        // New languages
        'c', 'cpp', 'cc', 'cxx', 'h', 'hpp',
        'rs',
        'lua',
        'rb',
        'php',
        'sh', 'bash',
        'html', 'css', 'scss', 'less',
        'cs',
        'scala',
        'r',
        'zig',
        'hs',
        'ex', 'exs',
      };
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

    // For Kotlin: generate R.jar BEFORE starting the LSP so the classpath is
    // correct from the first initialize request.
    //
    // Fallback chain (best → worst):
    //   1. aapt2 pipeline  → real R.jar with correct resource IDs
    //   2. javac stub      → stub R.jar with = 0 (needs javac, not aapt2)
    //   3. R.kt stub file  → source stub in lsp_stubs/ (last resort)
    String? generatedRJar;
    if (const {'kt', 'kotlin'}.contains(ext)) {
      generatedRJar = await _buildRJarWithAapt2(projectPath)
                   ?? await _buildStubRJar(projectPath);
      if (generatedRJar == null) _generateRStubIfNeeded(projectPath);
    }

    _lspConfig = QuillLspStdioConfig(
      executable: cmd.first,
      args: cmd.sublist(1),
      languageId: _languageId(extension),
      workspacePath: projectPath,
      // Pass Termux PATH so the LSP process can find node, python, etc.
      // Without this the process inherits the app's restricted environment.
      environment: _envForExtension(extension),
      initializeTimeoutSeconds: timeoutSecs,
      initializationOptions: _initOptionsForExtension(ext,
          projectPath: projectPath, generatedRJar: generatedRJar),
      // Give JVM servers 1.5 s to load class files before sending initialize.
      startupDelayMs: const {'kt', 'kotlin', 'java', 'xml'}.contains(ext) ? 1500 : 0,
    );
    _status = LspStatus.warming;
    notifyListeners();
  }

  void stop() {
    _scanCancelled = true;
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
    // Cancel any in-progress workspace scan from a previous session before
    // starting a new one.
    _scanCancelled = true;
    _allDiagSub?.cancel();
    _projectDiagnostics.clear();
    _activelyOpenUris.clear();
    _allDiagSub = client.listenAllDiagnostics((uri, diags) {
      final filtered = _filterFalsePositives(diags);
      if (filtered.isNotEmpty) {
        _projectDiagnostics[uri] = filtered;
      } else {
        _projectDiagnostics.remove(uri);
      }
      // Debounce: batch rapid notifications (e.g. 400-file workspace scan)
      // so the Problems panel doesn't trigger a rebuild for every file.
      _diagDebounceTimer?.cancel();
      // 120 ms: fast enough to feel immediate for single-file edits,
      // still coalesces bursts during workspace scan (60-file batches).
      _diagDebounceTimer = Timer(const Duration(milliseconds: 120), notifyListeners);

      markReady();
    });

    // The initialize handshake already completed before attachClient is called
    // (start() blocks until the server replies). Mark ready immediately so the
    // UI spinner disappears and the user can start editing with completions.
    markReady();

    // Delay the workspace scan so the server can process the active file's
    // didOpen first. JVM servers (Kotlin/Java/XML) are especially sensitive to
    // being flooded with 400 didOpen messages right after initialization.
    final langId = _lspConfig?.languageId ?? '';
    final isJvm = const {'kotlin', 'java', 'xml'}.contains(langId);
    final scanDelay = isJvm
        ? const Duration(seconds: 5)
        : const Duration(milliseconds: 500);
    Future<void>.delayed(scanDelay, () => _scanWorkspace(client));
  }

  /// Walk the workspace directory and send textDocument/didOpen for every file
  /// matching the current LSP language.  The server then analyses each file
  /// and pushes publishDiagnostics notifications that end up in
  /// [_projectDiagnostics] via [listenAllDiagnostics].
  ///
  /// Files are sent in small batches with a short pause between each batch so
  /// we don't flood the server (important for JVM-based servers like jdtls).
  Future<void> _scanWorkspace(LspClient client) async {
    _scanCancelled = false;

    final cfg = _lspConfig;
    if (cfg == null) return;

    // XML validation is per-file — LemMinX does not need a project-wide scan.
    // Skipping it prevents flooding the server with 400 didOpen messages and
    // significantly reduces startup time.
    if (cfg.languageId == 'xml') return;

    final exts = _extensionsForLanguageId(cfg.languageId);
    if (exts.isEmpty) return;

    // For Kotlin, only scan .kt files — .kts files (build.gradle.kts, etc.)
    // are Gradle scripts that require kotlin-scripting-runtime.jar to compile.
    // Without it, kotlin-ls emits "No script runtime found" errors for every
    // .kts file and attributes them to unexpected file positions.
    final scanExts = cfg.languageId == 'kotlin' ? const <String>{'kt'} : exts;

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

    // JVM servers (Kotlin, Java) are slow — limit files to avoid multi-minute
    // startup delays while the server processes the entire project.
    final isJvm = const {'kotlin', 'java'}.contains(cfg.languageId);
    final maxFiles = isJvm ? 60 : 400;

    final files = <File>[];

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
            if (dot != -1 && scanExts.contains(name.substring(dot + 1).toLowerCase())) {
              files.add(entity);
            }
          }
        }
      } catch (_) {}
    }

    collect(root);

    // JVM servers: smaller batches and longer pauses to avoid overwhelming the
    // analyser while it's still warming up.
    final batchSize = isJvm ? 3 : 5;
    final batchDelay =
        isJvm ? const Duration(milliseconds: 800) : const Duration(milliseconds: 400);

    for (var i = 0; i < files.length; i++) {
      if (_scanCancelled) break;
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
        if (_scanCancelled) break;
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
      case 'c':                   return {'c', 'h'};
      case 'cpp':                 return {'cpp', 'cc', 'cxx', 'hpp', 'h'};
      case 'rust':                return {'rs'};
      case 'lua':                 return {'lua'};
      case 'ruby':                return {'rb'};
      case 'php':                 return {'php', 'phtml'};
      case 'shellscript':         return {'sh', 'bash'};
      case 'html':                return {'html', 'htm'};
      case 'css':                 return {'css'};
      case 'scss':                return {'scss', 'sass'};
      case 'csharp':              return {'cs'};
      case 'scala':               return {'scala', 'sc'};
      case 'r':                   return {'r', 'R'};
      case 'zig':                 return {'zig'};
      case 'haskell':             return {'hs', 'lhs'};
      case 'elixir':              return {'ex', 'exs'};
      default:                    return {};
    }
  }

  /// Detach the current client's global diagnostics listener and clear the
  /// project-wide map.  Called when the LSP is stopped or the client is shut down.
  void detachClient() {
    _scanCancelled = true;
    _allDiagSub?.cancel();
    _allDiagSub = null;
    _diagDebounceTimer?.cancel();
    _diagDebounceTimer = null;
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
      case 'dart':                  return 'dart language-server --lsp';
      case 'js': case 'jsx':
      case 'ts': case 'tsx':        return 'typescript-language-server --stdio';
      case 'py':                    return 'python3 -m pylsp';
      case 'kt': case 'kotlin':     return 'kotlin-language-server';
      case 'java':                  return 'java -jar ${RuntimeEnvir.javaLsJar}';
      case 'go':                    return 'gopls';
      case 'swift':                 return 'sourcekit-lsp';
      case 'xml':                   return 'java -jar ~/opt/lemminx/lemminx.jar';
      case 'c': case 'cpp':
      case 'cc': case 'cxx':
      case 'h': case 'hpp':         return 'clangd --background-index';
      case 'rs':                    return 'rust-analyzer';
      case 'lua':                   return 'lua-language-server';
      case 'rb':                    return 'solargraph stdio';
      case 'php':                   return 'node ~/.nvm/lib/node_modules/intelephense/bin/intelephense.js --stdio';
      case 'sh': case 'bash':       return 'bash-language-server start';
      case 'html':                  return 'vscode-html-language-server --stdio';
      case 'css': case 'scss':      return 'vscode-css-language-server --stdio';
      case 'cs':                    return 'csharp-ls';
      case 'scala': case 'sc':      return 'metals';
      case 'r':                     return 'Rscript -e "languageserver::run()"';
      case 'zig':                   return 'zls';
      case 'hs': case 'lhs':        return 'haskell-language-server-wrapper --lsp';
      case 'ex': case 'exs':        return 'elixir-ls';
      default:                      return null;
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
        // -XX:TieredStopAtLevel=1 → skip heavy JIT → faster cold start.
        // --stdio flag does NOT exist in older LemMinX → omit it.
        return [
          java,
          '-Xmx128m', '-Xms16m',
          '-XX:TieredStopAtLevel=1',
          '-XX:+UseSerialGC',
          '-Dfile.encoding=UTF-8',
          '-jar', jar,
        ];

      // ── C / C++ (clangd) ──────────────────────────────────────────────────
      case 'c':
      case 'cpp':
      case 'cc':
      case 'cxx':
      case 'h':
      case 'hpp':
        final clangd = RuntimeEnvir.clangdBin;
        if (!File(clangd).existsSync()) return null;
        return [clangd, '--background-index', '--clang-tidy'];

      // ── Rust (rust-analyzer) ──────────────────────────────────────────────
      case 'rs':
        final ra = RuntimeEnvir.rustAnalyzerBin;
        if (!File(ra).existsSync()) return null;
        return [ra];

      // ── Lua (lua-language-server) ─────────────────────────────────────────
      case 'lua':
        final luaLs = RuntimeEnvir.luaLsBin;
        if (!File(luaLs).existsSync()) return null;
        return [luaLs];

      // ── Ruby (Solargraph) ─────────────────────────────────────────────────
      case 'rb':
        final solargraph = RuntimeEnvir.solargraphBin;
        if (!File(solargraph).existsSync()) return null;
        final bash = RuntimeEnvir.bashPath;
        return File(bash).existsSync() ? [bash, solargraph, 'stdio'] : [solargraph, 'stdio'];

      // ── PHP (Intelephense) ────────────────────────────────────────────────
      case 'php':
        final node = RuntimeEnvir.nodePath;
        if (!File(node).existsSync()) return null;
        final nmRoot = '${RuntimeEnvir.usrPath}/lib/node_modules';
        for (final rel in const [
          'intelephense/bin/intelephense.js',
          '@nicolo-ribaudo/intelephense/bin/intelephense.js',
        ]) {
          final js = '$nmRoot/$rel';
          if (File(js).existsSync()) return [node, js, '--stdio'];
        }
        return null;

      // ── Bash / Shell (bash-language-server) ───────────────────────────────
      case 'sh':
      case 'bash':
        final nodeB = RuntimeEnvir.nodePath;
        if (!File(nodeB).existsSync()) return null;
        final bashLsJs = '${RuntimeEnvir.usrPath}/lib/node_modules/bash-language-server/out/cli.js';
        if (File(bashLsJs).existsSync()) return [nodeB, bashLsJs, 'start'];
        return null;

      // ── HTML / CSS / SCSS (vscode-langservers-extracted) ─────────────────
      case 'html':
        final nodeH = RuntimeEnvir.nodePath;
        if (!File(nodeH).existsSync()) return null;
        final nmH = '${RuntimeEnvir.usrPath}/lib/node_modules/vscode-langservers-extracted';
        final htmlJs = '$nmH/bin/vscode-html-language-server.js';
        if (File(htmlJs).existsSync()) return [nodeH, htmlJs, '--stdio'];
        return null;

      case 'css':
      case 'scss':
      case 'less':
        final nodeC = RuntimeEnvir.nodePath;
        if (!File(nodeC).existsSync()) return null;
        final nmC = '${RuntimeEnvir.usrPath}/lib/node_modules/vscode-langservers-extracted';
        final cssJs = '$nmC/bin/vscode-css-language-server.js';
        if (File(cssJs).existsSync()) return [nodeC, cssJs, '--stdio'];
        return null;

      // ── C# (csharp-ls) ───────────────────────────────────────────────────
      case 'cs':
        final csLs = RuntimeEnvir.csharpLsBin;
        if (File(csLs).existsSync()) return [csLs];
        return null;

      // ── Scala (Metals) ────────────────────────────────────────────────────
      case 'scala':
      case 'sc':
        final metals = RuntimeEnvir.metalsBin;
        if (!File(metals).existsSync()) return null;
        return [metals];

      // ── R (r-languageserver) ──────────────────────────────────────────────
      case 'r':
        final rscript = RuntimeEnvir.rBin;
        if (!File(rscript).existsSync()) return null;
        return [rscript, '-e', 'languageserver::run()'];

      // ── Zig (zls) ────────────────────────────────────────────────────────
      case 'zig':
        final zls = RuntimeEnvir.zlsBin;
        if (!File(zls).existsSync()) return null;
        return [zls];

      // ── Haskell (HLS) ────────────────────────────────────────────────────
      case 'hs':
      case 'lhs':
        final hls = RuntimeEnvir.hlsBin;
        if (!File(hls).existsSync()) return null;
        return [hls, '--lsp'];

      // ── Elixir (ElixirLS) ─────────────────────────────────────────────────
      case 'ex':
      case 'exs':
        final elixirLs = RuntimeEnvir.elixirLsBin;
        if (!File(elixirLs).existsSync()) return null;
        final bash3 = RuntimeEnvir.bashPath;
        return File(bash3).existsSync() ? [bash3, elixirLs] : [elixirLs];

      default:
        return null;
    }
  }

  /// Returns a short human-readable message when a known LSP binary is missing.
  String _missingBinaryMessage(String ext) {
    switch (ext.toLowerCase()) {
      case 'java':
        return 'Java LSP (eclipse.jdt.ls) not found.\n'
            'Install the Android SDK extension and run its install steps.\n'
            'Expected jdtls at: ${RuntimeEnvir.jdtlsBin}';
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
      // Try alternative Termux package installation paths.
      final altPaths = [
        '${RuntimeEnvir.usrPath}/share/kotlin-language-server/server',
        '${RuntimeEnvir.homePath}/.local/share/kotlin-language-server/server',
      ];
      for (final alt in altPaths) {
        final altLib = Directory('$alt/lib');
        if (altLib.existsSync()) {
          debugPrint('[LspProvider] kotlin-ls found at alternative path: $alt');
          final altJars = altLib.listSync().whereType<File>()
              .where((f) => f.path.endsWith('.jar'))
              .map((f) => f.path)
              .toList()..sort();
          if (altJars.isNotEmpty) {
            return [java, '-Xmx384m', '-Xms64m', '-Xss2m',
              '-XX:TieredStopAtLevel=1', '-XX:+UseSerialGC',
              '-Dkotlin.daemon.enabled=false',
              '-classpath', altJars.join(':'),
              'org.javacs.kt.MainKt'];
          }
        }
      }
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
      '-Xss2m',                    // reduced from 4m — enough for kotlin-ls
      '-XX:TieredStopAtLevel=1',   // skip C2 JIT → ~30% faster cold start
      '-XX:+UseSerialGC',          // serial GC is best for small heaps on Android
      '-Dfile.encoding=UTF-8',
      '-Dkotlin.daemon.enabled=false', // prevent Kotlin from spawning a daemon
      '-classpath', classpath,
      'org.javacs.kt.MainKt',
    ];
  }

  /// Launches eclipse.jdt.ls (jdtls) — the Java LSP installed by the
  /// Android SDK extension at [RuntimeEnvir.jdtlsBin] / [RuntimeEnvir.jdtlsHome].
  ///
  /// Strategy:
  ///  1. Run via bash wrapper ($PREFIX/bin/jdtls) — the wrapper sets up the
  ///     correct JVM flags, module opens, and configuration paths.
  ///  2. Direct equinox-launcher invocation when no bash wrapper exists.
  ///  3. Legacy java-language-server jar as last resort (rarely installed).
  ///
  /// Returns null when neither jdtls nor java-language-server are installed.
  List<String>? _javaLsCommand() {
    final java = RuntimeEnvir.javaPath;
    if (!File(java).existsSync()) {
      debugPrint('[LspProvider] java not found at $java.'
          ' Install via: pkg install openjdk-17');
      return null;
    }

    // ── Strategy 1: jdtls bash wrapper (preferred) ───────────────────────────
    final jdtlsBin = RuntimeEnvir.jdtlsBin; // $PREFIX/bin/jdtls
    if (File(jdtlsBin).existsSync()) {
      final bash = RuntimeEnvir.bashPath;
      if (File(bash).existsSync()) {
        debugPrint('[LspProvider] using jdtls via bash: $jdtlsBin');
        return [bash, jdtlsBin];
      }
      // Termux ensures libtermux-exec.so so we can exec bash scripts directly.
      debugPrint('[LspProvider] using jdtls directly: $jdtlsBin');
      return [jdtlsBin];
    }

    // ── Strategy 2: direct equinox-launcher invocation ───────────────────────
    final pluginsDir = Directory('${RuntimeEnvir.jdtlsHome}/plugins');
    if (pluginsDir.existsSync()) {
      try {
        final launchers = pluginsDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.contains('org.eclipse.equinox.launcher_'))
            .toList();
        if (launchers.isNotEmpty) {
          final launcher = launchers.first.path;
          // Prefer Linux ARM64 config dir (Termux target), fall back to generic.
          final configDirs = [
            '${RuntimeEnvir.jdtlsHome}/config_linux_arm',
            '${RuntimeEnvir.jdtlsHome}/config_linux',
          ];
          final configDir =
              configDirs.firstWhere((d) => Directory(d).existsSync(),
                  orElse: () => configDirs.last);
          final dataDir = RuntimeEnvir.jdtlsDataPath;
          debugPrint('[LspProvider] launching jdtls equinox: $launcher');
          return [
            java,
            '-Xmx512m', '-Xms128m',
            '-XX:TieredStopAtLevel=1',
            '-Dfile.encoding=UTF-8',
            '--add-modules=ALL-SYSTEM',
            '--add-opens', 'java.base/java.util=ALL-UNNAMED',
            '--add-opens', 'java.base/java.lang=ALL-UNNAMED',
            '-jar', launcher,
            '-configuration', configDir,
            '-data', dataDir,
          ];
        }
      } catch (e) {
        debugPrint('[LspProvider] jdtls launcher search failed: $e');
      }
    }

    // ── Strategy 3: legacy java-language-server jar (fallback) ───────────────
    final jar = RuntimeEnvir.javaLsJar;
    if (File(jar).existsSync()) {
      debugPrint('[LspProvider] java-language-server fallback: $java -jar $jar');
      return [java, '-jar', jar];
    }

    debugPrint('[LspProvider] no Java LSP found (jdtls at ${RuntimeEnvir.jdtlsHome}'
        ' or java-language-server at $jar).');
    return null;
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

      // eclipse.jdt.ls (jdtls) — JAVA_HOME needed so the wrapper script finds
      // the correct JVM. When using direct equinox-launcher, heap flags are
      // passed on the command line, but JAVA_TOOL_OPTIONS is a safe fallback.
      case 'java':
        final jHome = RuntimeEnvir.javaHome;
        final javaEnv = <String, String>{...base};
        if (jHome.isNotEmpty) javaEnv['JAVA_HOME'] = jHome;
        // Only set JAVA_TOOL_OPTIONS for direct invocation; the wrapper
        // script has its own -Xmx setting. JAVA_TOOL_OPTIONS is additive and
        // can conflict with the script's heap flags, but for direct launch it
        // ensures the heap cap is applied.
        javaEnv['JAVA_TOOL_OPTIONS'] = '-Xmx512m -Xms64m -XX:TieredStopAtLevel=1';
        return javaEnv;
      case 'xml':
        // LemMinX: JVM flags are passed directly in the command (see xml case
        // in _lspServerCommand), so we only need JAVA_HOME here.
        final xmlJHome = RuntimeEnvir.javaHome;
        return xmlJHome.isNotEmpty
            ? <String, String>{...base, 'JAVA_HOME': xmlJHome}
            : <String, String>{...base};
      default:
        return base;
    }
  }

  /// Language-specific initialization options sent in the LSP initialize request.
  /// These fine-tune server behaviour without requiring filesystem config files.
  Map<String, dynamic>? _initOptionsForExtension(String ext,
      {String? projectPath, String? generatedRJar}) {
    switch (ext) {
      case 'kt':
      case 'kotlin':
        // Build the compiler classpath:
        //  1. android.jar      — Android SDK types (Activity, View, etc.)
        //  2. build R.jar      — real R class from Gradle build output (preferred)
        //  3. generated R.jar  — aapt2-generated R.jar (fallback when no build yet)
        // If a real Gradle R.jar exists we skip the generated one to avoid
        // "duplicate class" conflicts (both define the same R class).
        final androidJar  = _findAndroidJar();
        final buildRJars  = projectPath != null ? _findRClassJars(projectPath) : <String>[];
        // Prefer real build output; only use generated jar when build hasn't run.
        final rJars = buildRJars.isNotEmpty
            ? buildRJars
            : (generatedRJar != null ? [generatedRJar] : <String>[]);
        final classpath = <String>[
          if (androidJar != null) androidJar,
          ...rJars,
        ];
        return {
          'compiler': {
            'jvm': {
              'target': '1.8',
              // Provide android.jar + R.jar so the compiler finds Android types.
              if (classpath.isNotEmpty) 'classpath': classpath.join(':'),
            },
          },
          'completion': {
            'snippets': {'enabled': true},
          },
          'diagnostics': {'enabled': true},
          'inlayHints': {
            'typeHints': {'enabled': false},
            'parameterHints': {'enabled': false},
            'chainedHints': {'enabled': false},
          },
        };

      case 'java':
        // eclipse.jdt.ls (jdtls) initialization options.
        // settings.java.home: ensures jdtls uses the correct JDK.
        // referencedLibraries: adds android.jar so Android SDK types resolve.
        final jHome = RuntimeEnvir.javaHome;
        final androidJarJava = _findAndroidJar();
        return <String, dynamic>{
          'settings': {
            'java': {
              if (jHome.isNotEmpty) 'home': jHome,
              'format': {'enabled': true},
              'completion': {
                'enabled': true,
                'guessMethodArguments': false,
                'filteredTypes': ['java.awt.*', 'sun.*', 'javax.swing.*'],
              },
              'signatureHelp': {'enabled': true},
              'saveActions': {'organizeImports': false},
              'project': {
                if (androidJarJava != null)
                  'referencedLibraries': [androidJarJava],
              },
              'errors': {
                // Suppress unknown Android build annotation warnings
                'incompleteClasspath': {'severity': 'ignore'},
              },
            },
          },
          'extendedClientCapabilities': {
            'progressReportProvider': false,
            'classFileContentsSupport': false,
            'overrideMethodsPromptSupport': false,
            'hashCodeEqualsPromptSupport': false,
            'advancedOrganizeImportsSupport': false,
            'generateToStringPromptSupport': false,
            'advancedGenerateAccessorsSupport': false,
            'generateConstructorsPromptSupport': false,
            'generateDelegateMethodsPromptSupport': false,
            'advancedExtractRefactoringSupport': false,
            'inferSelectionSupport': <dynamic>[],
            'moveRefactoringSupport': false,
            'clientHoverProvider': false,
            'clientDocumentSymbolProvider': false,
            'gradleChecksumWrapperPromptSupport': false,
            'executeClientCommandSupport': false,
          },
        };

      case 'xml':
        // LemMinX: disable "no grammar" errors for Android XML files
        // (layouts, manifests, resources) that use custom Android namespaces.
        // The Android schema URI (schemas.android.com) can't be fetched at
        // runtime, so LemMinX would always error without noGrammar=ignore.
        return {
          'xml': {
            'catalogs': <String>[],
            'validation': {
              'enabled': true,
              // "ignore" suppresses errors/warnings for files with no
              // associated grammar — critical for Android XML files.
              'noGrammar': 'ignore',
              'disallowDocTypeDecl': false,
              'resolveExternalEntities': false,
              'schema': {'enabled': 'never'},
            },
            'format': {
              'enabled': true,
              'splitAttributes': false,
              'joinCDATALines': false,
              'formatComments': true,
              'joinCommentLines': false,
              'spaceBeforeEmptyCloseTag': true,
              'joinContentLines': false,
            },
            'completion': {
              'autoCloseTags': true,
              'autoCloseRemovesContent': true,
            },
            'hover': {'documentation': true, 'references': true},
            'codeLens': {'enabled': false},
          },
        };

      default:
        return null;
    }
  }

  /// Finds the highest-version android.jar in the Android SDK platforms dir.
  /// Returns null if the SDK is not installed or no platform is found.
  String? _findAndroidJar() {
    try {
      final platformsDir =
          Directory('${RuntimeEnvir.androidSdkPath}/platforms');
      if (!platformsDir.existsSync()) return null;
      final entries = platformsDir
          .listSync()
          .whereType<Directory>()
          .map((d) {
            final name = d.path.split('/').last.split('\\').last;
            final ver = int.tryParse(name.replaceFirst('android-', '')) ?? 0;
            return (dir: d, version: ver);
          })
          .where((e) => e.version > 0)
          .toList()
        ..sort((a, b) => b.version.compareTo(a.version));
      for (final entry in entries) {
        final jar = File('${entry.dir.path}/android.jar');
        if (jar.existsSync()) return jar.path;
      }
    } catch (_) {}
    return null;
  }

  /// Finds R.jar files in Android build output directories.
  ///
  /// AGP 7.0+ compiles the R class into per-module jars under:
  ///   {module}/build/intermediates/compile_r_class_jar/{variant}/R.jar
  ///
  /// Adding these jars to kotlin-ls classpath lets it resolve R.id, R.layout,
  /// R.string, etc. without a "Unresolved reference: R" diagnostic.
  /// Returns at most 3 jars (one per module) to keep the classpath short.
  List<String> _findRClassJars(String projectPath) {
    final jars = <String>[];
    try {
      final root = Directory(projectPath);
      if (!root.existsSync()) return jars;

      final skipDirs = const {
        '.git', '.gradle', '.idea', '.dart_tool', '.kotlin',
        'node_modules', '.pub-cache',
      };
      final intermediatePatterns = const [
        'compile_r_class_jar',
        'compile_and_runtime_not_namespaced_r_class_jar',
      ];

      // Check each top-level module directory (app, core, feature, etc.)
      for (final moduleEntity in root.listSync()) {
        if (jars.length >= 3) break;
        if (moduleEntity is! Directory) continue;
        final moduleName = moduleEntity.path.split('/').last.split('\\').last;
        if (skipDirs.contains(moduleName)) continue;

        final intermediates =
            Directory('${moduleEntity.path}/build/intermediates');
        if (!intermediates.existsSync()) continue;

        for (final pattern in intermediatePatterns) {
          final patDir = Directory('${intermediates.path}/$pattern');
          if (!patDir.existsSync()) continue;
          // Check each build variant (debug/release/…)
          for (final variantDir in patDir.listSync().whereType<Directory>()) {
            final jar = File('${variantDir.path}/R.jar');
            if (jar.existsSync()) {
              jars.add(jar.path);
              debugPrint('[LspProvider] found R.jar: ${jar.path}');
              break; // one variant per pattern is enough
            }
          }
          if (jars.isNotEmpty) break; // one pattern per module is enough
        }
      }
    } catch (_) {}
    return jars;
  }

  /// Filters out known false-positive LSP diagnostics that do not represent
  /// real errors in the user's project.
  ///
  /// XML: LemMinX may carry Kotlin scripting JARs in its bundle. When it tries
  ///   to initialise Kotlin scripting for XML schema validation and the runtime
  ///   is missing, it emits a "No script runtime" diagnostic attributed to the
  ///   active file (often AndroidManifest.xml:1:1). This is harmless noise.
  List<LspDiagnostic> _filterFalsePositives(List<LspDiagnostic> diags) {
    final langId = _lspConfig?.languageId ?? '';
    if (langId != 'xml') return diags;
    return diags.where((d) {
      final msg = d.message;
      // Kotlin scripting runtime missing — not a real XML error.
      if (msg.contains('kotlin.script.templates')) return false;
      if (msg.contains('No script runtime was found')) return false;
      if (msg.contains('ScriptTemplateWithArgs')) return false;
      return true;
    }).toList();
  }

  // ── aapt2 R.jar generator ─────────────────────────────────────────────────
  //
  // Generates a real, compiled R.jar using the Android build tools that are
  // already installed by the Android SDK extension:
  //
  //   aapt2 compile --dir res/ -o compiled/   → .flat resource files
  //   aapt2 link   compiled/*.flat -I android.jar --manifest ... --java gen/
  //                                            → R.java with real resource IDs
  //   javac -source 8 -target 8 R.java -d classes/
  //   jar cf R.jar -C classes/ .              → compiled R.class in a jar
  //
  // The result is cached in {project}/lsp_stubs/R.jar and regenerated only
  // when res/ has been modified since the last build (mtime check).
  // When aapt2 or javac are not available, falls back to a stub R.kt.

  /// Finds the highest-version `aapt2` binary in the Android SDK build-tools.
  String? _findAapt2() {
    try {
      final buildToolsDir =
          Directory('${RuntimeEnvir.androidSdkPath}/build-tools');
      if (!buildToolsDir.existsSync()) return null;

      final versions = buildToolsDir
          .listSync()
          .whereType<Directory>()
          .map((d) {
            final name = d.path.split('/').last.split('\\').last;
            final parts =
                name.split('.').map((s) => int.tryParse(s) ?? 0).toList();
            return (dir: d, version: parts);
          })
          .toList()
        ..sort((a, b) {
          for (int i = 0;
              i < a.version.length && i < b.version.length;
              i++) {
            final c = b.version[i].compareTo(a.version[i]);
            if (c != 0) return c;
          }
          return b.version.length.compareTo(a.version.length);
        });

      for (final v in versions) {
        final aapt2 = File('${v.dir.path}/aapt2');
        if (aapt2.existsSync()) return aapt2.path;
      }
    } catch (_) {}
    return null;
  }

  /// Returns (manifestPath, resPath) for the first AndroidManifest.xml found
  /// in the project tree. Checks common locations before doing a shallow scan.
  (String, String)? _findManifestAndRes(String projectPath) {
    for (final rel in const [
      'app/src/main/AndroidManifest.xml',
      'src/main/AndroidManifest.xml',
      'AndroidManifest.xml',
    ]) {
      final f = File('$projectPath/$rel');
      if (f.existsSync()) return (f.path, '${f.parent.path}/res');
    }
    // Shallow search for multi-module projects.
    try {
      final root = Directory(projectPath);
      for (final entity in root.listSync()) {
        if (entity is! Directory) continue;
        final name = entity.path.split('/').last.split('\\').last;
        if (name.startsWith('.') || name == 'build' || name == 'gradle') {
          continue;
        }
        final manifest =
            File('${entity.path}/src/main/AndroidManifest.xml');
        if (manifest.existsSync()) {
          return (manifest.path, '${manifest.parent.path}/res');
        }
      }
    } catch (_) {}
    return null;
  }

  /// Generates a real R.jar via aapt2 → javac pipeline.
  ///
  /// Returns the path to `{project}/lsp_stubs/R.jar` on success, or null
  /// when any required tool is missing or a step fails. In that case the
  /// caller falls back to the stub R.kt generator.
  Future<String?> _buildRJarWithAapt2(String projectPath) async {
    // ── Locate required tools ────────────────────────────────────────────────
    final aapt2 = _findAapt2();
    if (aapt2 == null) {
      debugPrint('[LspProvider] aapt2 not found — falling back to stub R.kt');
      return null;
    }

    final jHome = RuntimeEnvir.javaHome;
    final javac = jHome.isNotEmpty
        ? '$jHome/bin/javac'
        : '${RuntimeEnvir.usrPath}/bin/javac';
    if (!File(javac).existsSync()) {
      debugPrint('[LspProvider] javac not found at $javac');
      return null;
    }

    // `jar` command — try JAVA_HOME first, then Termux $PREFIX/bin.
    final jarBin = () {
      for (final p in [
        if (jHome.isNotEmpty) '$jHome/bin/jar',
        '${RuntimeEnvir.usrPath}/bin/jar',
      ]) {
        if (File(p).existsSync()) return p;
      }
      return null;
    }();
    // Fallback to `zip` when `jar` is absent (zip and jar share the same format).
    final zipBin = '${RuntimeEnvir.usrPath}/bin/zip';
    if (jarBin == null && !File(zipBin).existsSync()) {
      debugPrint('[LspProvider] neither jar nor zip found — cannot package R.class');
      return null;
    }

    // ── Locate project files ─────────────────────────────────────────────────
    final found = _findManifestAndRes(projectPath);
    if (found == null) {
      debugPrint('[LspProvider] AndroidManifest.xml not found in $projectPath');
      return null;
    }
    final (manifestPath, resPath) = found;
    if (!Directory(resPath).existsSync()) {
      debugPrint('[LspProvider] res/ not found at $resPath');
      return null;
    }

    final androidJar = _findAndroidJar();
    if (androidJar == null) {
      debugPrint('[LspProvider] android.jar not found — cannot link R.java');
      return null;
    }

    // ── Up-to-date check (mtime) ─────────────────────────────────────────────
    final stubDir  = Directory('$projectPath/lsp_stubs');
    final rJarFile = File('${stubDir.path}/R.jar');
    if (rJarFile.existsSync()) {
      final resMtime = _dirLastModified(Directory(resPath));
      if (resMtime.isBefore(rJarFile.lastModifiedSync())) {
        debugPrint('[LspProvider] R.jar is up-to-date — reusing');
        return rJarFile.path;
      }
    }

    await stubDir.create(recursive: true);
    final env = RuntimeEnvir.baseEnv;

    // ── Step 1: aapt2 compile ────────────────────────────────────────────────
    // Compiles each file in res/ into a binary .flat file.
    final compiledDir = '${stubDir.path}/compiled';
    await Directory(compiledDir).create(recursive: true);

    debugPrint('[LspProvider] aapt2 compile res/...');
    final compileResult = await Process.run(
      aapt2,
      ['compile', '--dir', resPath, '-o', compiledDir],
      environment: env,
    );
    if (compileResult.exitCode != 0) {
      debugPrint('[LspProvider] aapt2 compile failed '
          '(${compileResult.exitCode}): ${compileResult.stderr}');
      return null;
    }

    final flatFiles = Directory(compiledDir)
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.flat'))
        .map((f) => f.path)
        .toList();
    if (flatFiles.isEmpty) {
      debugPrint('[LspProvider] aapt2 compile: no .flat files produced');
      return null;
    }

    // ── Step 2: aapt2 link → R.java ─────────────────────────────────────────
    // Links the compiled resources and generates R.java with real IDs.
    final genDir = '${stubDir.path}/gen';
    await Directory(genDir).create(recursive: true);
    final outApk = '${stubDir.path}/out.apk';

    debugPrint('[LspProvider] aapt2 link (${flatFiles.length} resources)...');
    final linkResult = await Process.run(
      aapt2,
      [
        'link',
        ...flatFiles,
        '-I', androidJar,
        '--manifest', manifestPath,
        '-o', outApk,
        '--java', genDir,
        // Allow package IDs below 0x7f (required for library modules).
        '--allow-reserved-package-id',
      ],
      environment: env,
    );
    if (linkResult.exitCode != 0) {
      debugPrint('[LspProvider] aapt2 link failed '
          '(${linkResult.exitCode}): ${linkResult.stderr}');
      return null;
    }

    // ── Step 3: find the generated R.java ────────────────────────────────────
    final rJavaFiles = <String>[];
    void findRJava(Directory dir) {
      try {
        for (final e in dir.listSync()) {
          if (e is File && e.path.endsWith('R.java')) {
            rJavaFiles.add(e.path);
          } else if (e is Directory) {
            findRJava(e);
          }
        }
      } catch (_) {}
    }
    findRJava(Directory(genDir));
    if (rJavaFiles.isEmpty) {
      debugPrint('[LspProvider] aapt2 link produced no R.java in $genDir');
      return null;
    }
    debugPrint('[LspProvider] R.java: ${rJavaFiles.first}');

    // ── Step 4: javac R.java → .class files ─────────────────────────────────
    final classDir = '${stubDir.path}/classes';
    await Directory(classDir).create(recursive: true);

    debugPrint('[LspProvider] javac R.java...');
    final javacResult = await Process.run(
      javac,
      [
        '-source', '8', '-target', '8',
        '-cp', androidJar,
        ...rJavaFiles,
        '-d', classDir,
      ],
      environment: env,
    );
    if (javacResult.exitCode != 0) {
      debugPrint('[LspProvider] javac failed '
          '(${javacResult.exitCode}): ${javacResult.stderr}');
      return null;
    }

    // ── Step 5: package .class files into R.jar ──────────────────────────────
    debugPrint('[LspProvider] packaging R.jar...');
    if (jarBin != null) {
      final jarResult = await Process.run(
        jarBin,
        ['cf', rJarFile.path, '-C', classDir, '.'],
        environment: env,
      );
      if (jarResult.exitCode != 0) {
        debugPrint('[LspProvider] jar failed: ${jarResult.stderr}');
        return null;
      }
    } else {
      // zip fallback: create jar from the classes directory.
      final zipResult = await Process.run(
        zipBin,
        ['-r', rJarFile.path, '.'],
        workingDirectory: classDir,
        environment: env,
      );
      if (zipResult.exitCode != 0) {
        debugPrint('[LspProvider] zip→jar failed: ${zipResult.stderr}');
        return null;
      }
    }

    debugPrint('[LspProvider] R.jar ready: ${rJarFile.path}');
    return rJarFile.path;
  }

  /// Generates a stub R.jar using only javac (no aapt2 required).
  ///
  /// Scans res/ to collect resource names → writes R.java with `= 0` stubs →
  /// compiles with javac → packages into R.jar.
  ///
  /// Values are placeholder (0), but identifiers are real, so kotlin-ls can
  /// resolve R.id.foo, R.layout.bar, etc. without "Unresolved reference: R".
  /// Called when aapt2 is not installed but javac is available.
  Future<String?> _buildStubRJar(String projectPath) async {
    // ── Locate javac ────────────────────────────────────────────────────────
    final jHome = RuntimeEnvir.javaHome;
    final javac = jHome.isNotEmpty
        ? '$jHome/bin/javac'
        : '${RuntimeEnvir.usrPath}/bin/javac';
    if (!File(javac).existsSync()) {
      debugPrint('[LspProvider] javac not found — cannot build stub R.jar');
      return null;
    }

    final jarBin = () {
      for (final p in [
        if (jHome.isNotEmpty) '$jHome/bin/jar',
        '${RuntimeEnvir.usrPath}/bin/jar',
      ]) {
        if (File(p).existsSync()) return p;
      }
      return null;
    }();
    final zipBin = '${RuntimeEnvir.usrPath}/bin/zip';
    if (jarBin == null && !File(zipBin).existsSync()) {
      debugPrint('[LspProvider] neither jar nor zip found');
      return null;
    }

    // ── Locate project files ────────────────────────────────────────────────
    final found = _findManifestAndRes(projectPath);
    if (found == null) return null;
    final (manifestPath, resPath) = found;

    String? packageName;
    try {
      packageName = _manifestPackage
          .firstMatch(File(manifestPath).readAsStringSync())
          ?.group(1);
    } catch (_) {}
    if (packageName == null) return null;

    final resDir = Directory(resPath);
    if (!resDir.existsSync()) return null;

    // ── Up-to-date check ────────────────────────────────────────────────────
    final stubDir  = Directory('$projectPath/lsp_stubs');
    final rJarFile = File('${stubDir.path}/R.jar');
    if (rJarFile.existsSync()) {
      if (_dirLastModified(resDir).isBefore(rJarFile.lastModifiedSync())) {
        debugPrint('[LspProvider] stub R.jar up-to-date');
        return rJarFile.path;
      }
    }

    await stubDir.create(recursive: true);
    final env = RuntimeEnvir.baseEnv;

    // ── Generate R.java ─────────────────────────────────────────────────────
    final resources = _collectAndroidResources(resDir);
    final rJavaPath = '${stubDir.path}/R.java';
    await File(rJavaPath).writeAsString(
        _buildRJavaStub(packageName, resources));

    // ── javac R.java ────────────────────────────────────────────────────────
    final classDir = '${stubDir.path}/classes';
    await Directory(classDir).create(recursive: true);

    final androidJar = _findAndroidJar();
    final javacArgs = <String>[
      '-source', '8', '-target', '8',
      if (androidJar != null) ...[ '-cp', androidJar ],
      rJavaPath,
      '-d', classDir,
    ];

    debugPrint('[LspProvider] javac stub R.java...');
    final javacResult = await Process.run(javac, javacArgs, environment: env);
    if (javacResult.exitCode != 0) {
      debugPrint('[LspProvider] javac stub failed: ${javacResult.stderr}');
      return null;
    }

    // ── Package into R.jar ──────────────────────────────────────────────────
    if (jarBin != null) {
      final r = await Process.run(
          jarBin, ['cf', rJarFile.path, '-C', classDir, '.'],
          environment: env);
      if (r.exitCode != 0) { debugPrint('[LspProvider] jar failed: ${r.stderr}'); return null; }
    } else {
      final r = await Process.run(zipBin, ['-r', rJarFile.path, '.'],
          workingDirectory: classDir, environment: env);
      if (r.exitCode != 0) { debugPrint('[LspProvider] zip failed: ${r.stderr}'); return null; }
    }

    debugPrint('[LspProvider] stub R.jar ready: ${rJarFile.path}');
    return rJarFile.path;
  }

  /// Generates R.java source from collected Android resources.
  /// Uses Java (not Kotlin) so it can be compiled by javac without kotlinc.
  static String _buildRJavaStub(
      String packageName, Map<String, Set<String>> resources) {
    final buf = StringBuffer()
      ..writeln('/* Auto-generated by fl_ide — do not edit */')
      ..writeln('package $packageName;')
      ..writeln()
      ..writeln('public final class R {');

    final types = resources.keys.toList()..sort();
    for (final type in types) {
      final names = resources[type]!.toList()..sort();
      buf.writeln('    public static final class $type {');
      for (final name in names) {
        buf.writeln('        public static final int $name = 0;');
      }
      buf.writeln('    }');
    }
    buf.writeln('}');
    return buf.toString();
  }

  // ── Android R stub generator (R.kt last-resort fallback) ─────────────────
  //
  // Used only when both aapt2 and javac are unavailable.
  // Generates a stub R.kt in {projectPath}/lsp_stubs/ (non-hidden, so
  // kotlin-ls's own workspace scan picks it up automatically).
  // Values are all = 0 but identifiers are real, stopping "Unresolved R".
  //
  // Android resource type mapping:
  //   res/layout/*.xml         → R.layout.<filename>
  //   res/drawable/**          → R.drawable.<filename>
  //   res/mipmap/**            → R.mipmap.<filename>
  //   res/menu/*.xml           → R.menu.<filename>
  //   res/anim/*.xml           → R.anim.<filename>
  //   res/animator/*.xml       → R.animator.<filename>
  //   res/raw/**               → R.raw.<filename>
  //   res/xml/*.xml            → R.xml.<filename>
  //   res/font/**              → R.font.<filename>
  //   res/values/*.xml         → parse <name> attrs → R.string/color/dimen/…
  //   @+id/foo in any XML      → R.id.foo

  static final _xmlNameAttr    = RegExp(r'name\s*=\s*"([^"]+)"');
  static final _xmlIdRef        = RegExp(r'@\+id/([A-Za-z_][A-Za-z0-9_.]*)', multiLine: true);
  static final _manifestPackage = RegExp(r'package\s*=\s*"([^"]+)"');

  /// Scans the Android project and writes lsp_stubs/R.kt if missing or stale.
  Future<void> _generateRStubIfNeeded(String projectPath) async {
    try {
      // Find AndroidManifest.xml via the shared helper.
      final found = _findManifestAndRes(projectPath);
      if (found == null) return;
      final (manifestPath, resRoot) = found;

      // Extract package name from the manifest.
      String? packageName;
      try {
        final text = File(manifestPath).readAsStringSync();
        packageName = _manifestPackage.firstMatch(text)?.group(1);
      } catch (_) {}
      if (packageName == null) return;

      final stubDir  = Directory('$projectPath/lsp_stubs');
      final stubFile = File('${stubDir.path}/R.kt');

      // Check if we need to regenerate: compare mtime of res/ vs stub file.
      final resDir = Directory(resRoot);
      if (!resDir.existsSync()) return;
      if (stubFile.existsSync()) {
        final stubMtime = stubFile.lastModifiedSync();
        final resMtime  = _dirLastModified(resDir);
        if (resMtime.isBefore(stubMtime)) {
          debugPrint('[LspProvider] R stub up-to-date — skipping generation');
          return; // stub is fresh
        }
      }

      // Collect all resource IDs from the res/ tree.
      final resources = _collectAndroidResources(resDir);

      final content = _buildRKtStub(packageName, resources);
      await stubDir.create(recursive: true);
      await stubFile.writeAsString(content);
      debugPrint('[LspProvider] generated R stub at ${stubFile.path}'
          ' (${resources.values.fold(0, (a, b) => a + b.length)} entries)');
    } catch (e) {
      debugPrint('[LspProvider] R stub generation error: $e');
    }
  }

  /// Returns the most recent mtime across all files in [dir] (non-recursive
  /// for performance — just the top-level res/ subdirectories are enough).
  DateTime _dirLastModified(Directory dir) {
    var latest = DateTime.fromMillisecondsSinceEpoch(0);
    try {
      for (final sub in dir.listSync()) {
        final m = sub.statSync().modified;
        if (m.isAfter(latest)) latest = m;
      }
    } catch (_) {}
    return latest;
  }

  /// Scans an Android `res/` directory and returns a map from resource type
  /// (e.g. 'layout', 'string', 'id') to a set of sanitized resource names.
  Map<String, Set<String>> _collectAndroidResources(Directory resDir) {
    final result = <String, Set<String>>{};
    void add(String type, String name) {
      final key = _sanitizeResName(name);
      if (key.isNotEmpty) (result[type] ??= {}).add(key);
    }

    try {
      for (final typeDir in resDir.listSync().whereType<Directory>()) {
        // res/ subdirs are like layout/, drawable-hdpi/, values-night/, etc.
        // The resource type is the part before the first '-'.
        final rawType = typeDir.path.split('/').last.split('\\').last;
        final resType = rawType.split('-').first.toLowerCase();

        for (final file in typeDir.listSync().whereType<File>()) {
          final fileName = file.path.split('/').last.split('\\').last;
          final dot      = fileName.lastIndexOf('.');
          final baseName = dot == -1 ? fileName : fileName.substring(0, dot);
          final ext      = dot == -1 ? '' : fileName.substring(dot + 1).toLowerCase();

          switch (resType) {
            case 'layout':
            case 'menu':
            case 'anim':
            case 'animator':
            case 'transition':
            case 'interpolator':
            case 'xml':
              if (ext == 'xml') add(resType, baseName);

            case 'drawable':
            case 'mipmap':
            case 'color':
            case 'raw':
            case 'font':
              add(resType, baseName);

            case 'values':
              if (ext != 'xml') break;
              try {
                final text = file.readAsStringSync();
                // Parse named resource declarations.
                final type2 = _valuesFileType(fileName);
                for (final m in _xmlNameAttr.allMatches(text)) {
                  final n = m.group(1) ?? '';
                  if (n.isEmpty) continue;
                  // styles have names like "AppTheme.Primary" → keep dots
                  if (type2 == 'style' || type2 == 'attr') {
                    add(type2, n.replaceAll('.', '_'));
                  } else {
                    add(type2, n);
                  }
                }
                // Also harvest @+id/foo from any values XML.
                for (final m in _xmlIdRef.allMatches(text)) {
                  add('id', m.group(1) ?? '');
                }
              } catch (_) {}

            default:
              // Unknown resource type — use the directory name as-is.
              if (ext == 'xml' || dot == -1) add(resType, baseName);
          }

          // Harvest @+id/foo from any XML file (layouts, menus, etc.)
          if (ext == 'xml' && resType != 'values') {
            try {
              final text = file.readAsStringSync();
              for (final m in _xmlIdRef.allMatches(text)) {
                add('id', m.group(1) ?? '');
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    return result;
  }

  /// Maps values/ XML filename to a resource type.
  static String _valuesFileType(String fileName) {
    final base = fileName.split('-').first.split('.').first.toLowerCase();
    return switch (base) {
      'strings' || 'string'     => 'string',
      'colors'  || 'color'      => 'color',
      'dimens'  || 'dimen'      => 'dimen',
      'styles'  || 'style'      => 'style',
      'attrs'   || 'attr'       => 'attr',
      'integers'|| 'integer'    => 'integer',
      'bools'   || 'bool'       => 'bool',
      'arrays'                  => 'array',
      'ids'     || 'id'         => 'id',
      _                         => base,
    };
  }

  /// Converts a resource name to a valid Kotlin identifier.
  /// Android names use dots and hyphens (e.g. "AppTheme.Primary", "ic-launcher").
  static String _sanitizeResName(String name) {
    return name.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '_');
  }

  /// Builds the contents of the stub R.kt file from collected resources.
  static String _buildRKtStub(
      String packageName, Map<String, Set<String>> resources) {
    final buf = StringBuffer()
      ..writeln('// Auto-generated by fl_ide for LSP resolution.')
      ..writeln('// Delete lsp_stubs/ to regenerate, or run a Gradle build.')
      ..writeln('@file:Suppress("unused", "ClassName", "MemberVisibilityCanBePrivate")')
      ..writeln()
      ..writeln('package $packageName')
      ..writeln()
      ..writeln('object R {');

    // Sort types for deterministic output (avoids unnecessary file rewrites).
    final types = resources.keys.toList()..sort();
    for (final type in types) {
      final names = resources[type]!.toList()..sort();
      buf.writeln('    object $type {');
      for (final name in names) {
        buf.writeln('        const val $name: Int = 0');
      }
      buf.writeln('    }');
    }
    buf.writeln('}');
    return buf.toString();
  }

  String _languageId(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':          return 'dart';
      case 'js':            return 'javascript';
      case 'jsx':           return 'javascriptreact';
      case 'ts':            return 'typescript';
      case 'tsx':           return 'typescriptreact';
      case 'mjs':           return 'javascript';
      case 'py':            return 'python';
      case 'kt':
      case 'kotlin':        return 'kotlin';
      case 'java':          return 'java';
      case 'go':            return 'go';
      case 'swift':         return 'swift';
      case 'xml':           return 'xml';
      case 'c':             return 'c';
      case 'cpp':
      case 'cc':
      case 'cxx':           return 'cpp';
      case 'h':
      case 'hpp':           return 'cpp';
      case 'rs':            return 'rust';
      case 'lua':           return 'lua';
      case 'rb':            return 'ruby';
      case 'php':           return 'php';
      case 'sh':
      case 'bash':          return 'shellscript';
      case 'html':          return 'html';
      case 'css':           return 'css';
      case 'scss':          return 'scss';
      case 'less':          return 'less';
      case 'cs':            return 'csharp';
      case 'scala':
      case 'sc':            return 'scala';
      case 'r':             return 'r';
      case 'zig':           return 'zig';
      case 'hs':
      case 'lhs':           return 'haskell';
      case 'ex':
      case 'exs':           return 'elixir';
      case 'toml':          return 'toml';
      case 'yaml':
      case 'yml':           return 'yaml';
      case 'json':          return 'json';
      case 'md':            return 'markdown';
      default:              return ext;
    }
  }

  /// Invoked by [MemoryPressureService] when Android signals moderate memory
  /// pressure (TRIM_MEMORY_RUNNING_LOW, level >= 10).
  /// Evicts diagnostics for files that are NOT currently open in the editor,
  /// keeping only the data the user is actively looking at.
  void _onMemoryPressure() {
    final evicted = _projectDiagnostics.keys
        .where((uri) => !_activelyOpenUris.contains(uri))
        .toList();
    if (evicted.isEmpty) return;
    for (final uri in evicted) {
      _projectDiagnostics.remove(uri);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    MemoryPressureService.instance.removeModerateListener(_onMemoryPressure);
    _allDiagSub?.cancel();
    _diagDebounceTimer?.cancel();
    stop();
    super.dispose();
  }
}
