import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build_runner_pkg/build_runner_pkg.dart' show BuildProvider;
import 'package:core/core.dart' show Project, RuntimeEnvir, SdkType;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Full remote build pipeline:
///   1. Ensure git is initialized in the project
///   2. Fetch GitHub user info via token (name, email, username)
///   3. Set git identity if not configured
///   4. Create / locate GitHub repo, add remote origin
///   5. Generate .gitignore if missing
///   6. Create GitHub Actions workflow
///   7. git add + commit + push
///   8. Poll run until complete
///   9. Download APK → return path for install dialog
class RemoteGitBuildProvider extends ChangeNotifier {
  bool _isRunning  = false;
  bool _cancelled  = false;

  bool get isRunning => _isRunning;

  /// Requests cancellation of the in-progress build.
  void cancel() {
    if (!_isRunning) return;
    _cancelled = true;
    notifyListeners();
  }

  // ── Entry point ───────────────────────────────────────────────────────────

  Future<void> start({
    required Project project,
    required BuildProvider buildProv,
    required String githubToken,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _cancelled = false;
    notifyListeners();

    buildProv.startManual();

    try {
      _log(buildProv, 'Compilacao Remota com GitHub Actions\n'
          '─────────────────────────────────────\n\n');

      // ── Step 1: verify git is available ──────────────────────────────────
      final gitOk = await _checkGitAvailable();
      if (!gitOk) {
        _log(buildProv, 'ERRO: git nao encontrado.\n'
            '   Instale via: pkg install git\n');
        buildProv.finishManual(success: false);
        return;
      }

      // ── Step 2: fetch GitHub user info ───────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, 'Obtendo informacoes do usuario GitHub...\n');
      final userInfo = await _fetchGitHubUser(githubToken);
      if (userInfo == null) {
        _log(buildProv, 'ERRO: Token invalido ou sem permissao.\n'
            '   Certifique-se de que o PAT tem escopo "repo" e "workflow".\n');
        buildProv.finishManual(success: false);
        return;
      }
      final ghLogin = userInfo['login'] as String;
      final ghName  = (userInfo['name']  as String?) ?? ghLogin;
      final ghEmail = (userInfo['email'] as String?) ?? '$ghLogin@users.noreply.github.com';
      _log(buildProv, '   Usuario: $ghLogin ($ghName)\n');

      // ── Step 3: ensure git repo ───────────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, '\nVerificando repositorio git local...\n');
      await _ensureGitInit(project.path, buildProv);

      // ── Step 4: set git identity ──────────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      await _ensureGitIdentity(project.path, ghName, ghEmail, buildProv);

      // ── Step 5: create/link GitHub repo + set origin ─────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, '\nVerificando repositorio no GitHub...\n');
      final repoName = _sanitizeRepoName(project.name);
      final (owner, repo) = await _ensureGitHubRepo(
        projectPath: project.path,
        login: ghLogin,
        repoName: repoName,
        token: githubToken,
        buildProv: buildProv,
      );
      _log(buildProv, '   Repositorio: $owner/$repo\n');

      // ── Step 6: .gitignore ────────────────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      await _ensureGitignore(project);

      // ── Step 7: workflow YAML ─────────────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, '\nVerificando GitHub Actions workflow...\n');
      final workflowPath =
          '${project.path}/.github/workflows/fl_ide_build.yml';
      await _ensureWorkflow(project, workflowPath, buildProv);

      // ── Step 8: commit + push ─────────────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, '\nEnviando alteracoes para o GitHub...\n');
      final pushOk = await _gitPush(
        project.path,
        buildProv,
        sdk: project.sdk,
        token: githubToken,
        login: ghLogin,
      );
      if (!pushOk) {
        buildProv.finishManual(success: false);
        return;
      }

      // ── Step 9: wait for run to appear ────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, '\nAguardando inicio da compilacao no GitHub Actions...\n');
      final runId = await _waitForRun(
        owner: owner,
        repo: repo,
        token: githubToken,
        buildProv: buildProv,
      );
      if (runId == null) {
        _log(buildProv, 'ERRO: Nenhuma execucao encontrada apos 3 minutos.\n'
            '   Verifique se o workflow foi criado corretamente.\n');
        buildProv.finishManual(success: false);
        return;
      }
      _log(buildProv, 'Run #$runId iniciado\n');

      // ── Step 10: poll until done ──────────────────────────────────────────
      final completed = await _pollUntilDone(
        owner: owner,
        repo: repo,
        runId: runId,
        token: githubToken,
        buildProv: buildProv,
      );
      if (!completed) {
        buildProv.finishManual(success: false);
        return;
      }

      // ── Step 11: download APK ─────────────────────────────────────────────
      if (_checkCancelled(buildProv)) return;
      _log(buildProv, '\nBaixando APK...\n');
      final apkPath = await _downloadApk(
        owner: owner,
        repo: repo,
        runId: runId,
        token: githubToken,
        projectPath: project.path,
        buildProv: buildProv,
      );

      buildProv.finishManual(success: apkPath != null, apkPath: apkPath);
      if (apkPath != null) {
        _log(buildProv, '\nAPK pronto:\n   $apkPath\n');
      }
    } catch (e, st) {
      buildProv.appendManualOutput('\nERRO inesperado: $e\n$st\n');
      buildProv.finishManual(success: false);
    } finally {
      _isRunning  = false;
      _cancelled  = false;
      notifyListeners();
    }
  }

  /// Returns true and logs a message if the user cancelled the build.
  bool _checkCancelled(BuildProvider bp) {
    if (!_cancelled) return false;
    _log(bp, '\nCompilacao remota cancelada pelo usuario.\n');
    bp.finishManual(success: false);
    return true;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _log(BuildProvider bp, String msg) => bp.appendManualOutput(msg);

  // ── Step helpers ──────────────────────────────────────────────────────────

  Future<bool> _checkGitAvailable() async {
    try {
      final r = await Process.run('git', ['--version'],
          environment: RuntimeEnvir.baseEnv);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> _fetchGitHubUser(String token) async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.github.com/user'),
              headers: _headers(token))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return jsonDecode(resp.body) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _ensureGitInit(String projectPath, BuildProvider bp) async {
    final gitDir = Directory('$projectPath/.git');
    if (gitDir.existsSync()) {
      _log(bp, '   Repositorio git ja existe\n');
      return;
    }
    _log(bp, '   Inicializando repositorio git...\n');
    await _run(['git', 'init'], projectPath);
    await _run(['git', 'checkout', '-b', 'main'], projectPath);
    _log(bp, '   git init concluido\n');
  }

  Future<void> _ensureGitIdentity(
    String projectPath,
    String name,
    String email,
    BuildProvider bp,
  ) async {
    // Check local config first, then global.
    final localName = await _gitConfig('user.name', projectPath, global: false);
    if (localName.isNotEmpty) return; // already set locally

    final globalName = await _gitConfig('user.name', projectPath, global: true);
    if (globalName.isNotEmpty) return; // already set globally

    _log(bp, '\nConfigurando identidade git ($name / $email)...\n');
    await _run(
        ['git', 'config', '--local', 'user.name', name], projectPath);
    await _run(
        ['git', 'config', '--local', 'user.email', email], projectPath);
    _log(bp, '   Identidade configurada\n');
  }

  /// Returns (owner, repo). Creates the GitHub repo if it doesn't exist,
  /// then sets or verifies the remote origin.
  Future<(String, String)> _ensureGitHubRepo({
    required String projectPath,
    required String login,
    required String repoName,
    required String token,
    required BuildProvider buildProv,
  }) async {
    // Does origin already exist?
    final existingUrl = await _gitRemoteUrl(projectPath);
    if (existingUrl != null && existingUrl.isNotEmpty) {
      final parsed = _parseGithubOwnerRepo(existingUrl);
      if (parsed != null) {
        _log(buildProv, '   Remote origin ja configurado\n');
        return parsed;
      }
    }

    // Try to use existing repo on GitHub first.
    final existsOnGH = await _repoExists(login, repoName, token);
    if (!existsOnGH) {
      _log(buildProv, '   Criando repositorio "$repoName" no GitHub...\n');
      final created = await _createRepo(repoName, token);
      if (!created) {
        _log(buildProv, '   (repositorio pode ja existir, continuando...)\n');
      } else {
        _log(buildProv, '   Repositorio criado\n');
      }
    } else {
      _log(buildProv, '   Repositorio ja existe no GitHub\n');
    }

    // Set remote origin using HTTPS + token for push auth.
    final remoteUrl =
        'https://$login:$token@github.com/$login/$repoName.git';
    if (existingUrl == null || existingUrl.isEmpty) {
      await _run(['git', 'remote', 'add', 'origin', remoteUrl], projectPath);
    } else {
      await _run(
          ['git', 'remote', 'set-url', 'origin', remoteUrl], projectPath);
    }
    _log(buildProv, '   Remote origin configurado\n');
    return (login, repoName);
  }

  Future<bool> _repoExists(
      String owner, String repo, String token) async {
    try {
      final resp = await http
          .get(Uri.parse('https://api.github.com/repos/$owner/$repo'),
              headers: _headers(token))
          .timeout(const Duration(seconds: 10));
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _createRepo(String name, String token) async {
    try {
      final resp = await http
          .post(
            Uri.parse('https://api.github.com/user/repos'),
            headers: {
              ..._headers(token),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'name': name,
              'private': false,
              'auto_init': false,
            }),
          )
          .timeout(const Duration(seconds: 15));
      return resp.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  Future<void> _ensureGitignore(Project project) async {
    final path = '${project.path}/.gitignore';
    if (File(path).existsSync()) return;
    await File(path).writeAsString(_gitignoreFor(project.sdk));
  }

  Future<void> _ensureWorkflow(
      Project project, String workflowPath, BuildProvider bp) async {
    final sdkVersions = await _detectSdkVersions(project.sdk, project.path);
    _log(bp, '   Versões detectadas: $sdkVersions\n');

    final file = File(workflowPath);
    final expected = _workflowYaml(project.sdk, sdkVersions);
    final alreadyExists = file.existsSync();
    if (alreadyExists && file.readAsStringSync() == expected) {
      _log(bp, '   Workflow ja esta atualizado\n');
      return;
    }
    _log(bp, '   ${alreadyExists ? "Atualizando" : "Criando"} workflow GitHub Actions...\n');
    await Directory(file.parent.path).create(recursive: true);
    await file.writeAsString(expected);
    _log(bp, '   .github/workflows/fl_ide_build.yml ${alreadyExists ? "atualizado" : "criado"}\n');
  }

  /// Detects the relevant SDK versions from the local environment.
  Future<Map<String, String>> _detectSdkVersions(
      SdkType sdk, String projectPath) async {
    final versions = <String, String>{};

    switch (sdk) {
      case SdkType.flutter:
        // Read Flutter version from the installed SDK's version file.
        final versionFile = File('${RuntimeEnvir.flutterPath}/version');
        if (versionFile.existsSync()) {
          final v = versionFile.readAsStringSync().trim();
          if (v.isNotEmpty) versions['flutter'] = v;
        }
        // Fallback: run `flutter --version --machine` to get exact version.
        if (!versions.containsKey('flutter')) {
          try {
            final r = await Process.run(
              'flutter', ['--version', '--machine'],
              environment: RuntimeEnvir.baseEnv,
            );
            if (r.exitCode == 0) {
              final json = jsonDecode(r.stdout as String) as Map<String, dynamic>;
              final v = json['frameworkVersion'] as String?;
              if (v != null && v.isNotEmpty) versions['flutter'] = v;
            }
          } catch (_) {}
        }

      case SdkType.androidSdk:
        versions['java'] = _detectJavaVersion();

      case SdkType.reactNative:
        // Detect Node.js major version.
        try {
          final r = await Process.run(
            'node', ['--version'],
            environment: RuntimeEnvir.baseEnv,
          );
          if (r.exitCode == 0) {
            final raw = (r.stdout as String).trim().replaceFirst('v', '');
            final major = raw.split('.').first;
            if (major.isNotEmpty) versions['node'] = major;
          }
        } catch (_) {}
        versions['java'] = _detectJavaVersion();

      default:
        break;
    }

    return versions;
  }

  /// Reads Java major version from the JAVA_HOME path (e.g. java-17-openjdk → '17').
  String _detectJavaVersion() {
    final javaHome = RuntimeEnvir.javaHome;
    if (javaHome.isEmpty) return '17';
    final match = RegExp(r'java-(\d+)').firstMatch(javaHome);
    return match?.group(1) ?? '17';
  }

  Future<bool> _gitPush(
    String projectPath,
    BuildProvider bp, {
    required SdkType sdk,
    required String token,
    required String login,
  }) async {
    // Untrack files that are now gitignored but may have been committed before
    // (e.g. android/local.properties which contains device-specific SDK paths).
    await _run(
      ['git', 'rm', '--cached', '-r', '--ignore-unmatch',
        'android/local.properties', 'android/key.properties'],
      projectPath,
    );

    // React Native: the android/ folder must be committed. If the project's
    // existing .gitignore ignores it (e.g. Expo template), force-add it so CI
    // can build. We force-add only the source tree, not build artifacts.
    if (sdk == SdkType.reactNative) {
      await _run(
        ['git', 'add', '--force', 'android/'],
        projectPath,
      );
    }

    // Stage everything.
    await _runLogged(['git', 'add', '-A'], projectPath, bp);

    // Commit (--allow-empty handles the case of no changes).
    final msg =
        'FL IDE remote build — ${DateTime.now().toIso8601String()}';
    await _runLogged(
        ['git', 'commit', '-m', msg, '--allow-empty'], projectPath, bp);

    // Determine current branch.
    final branch = await _currentBranch(projectPath);

    // Push — set upstream on first push.
    final pushArgs = [
      'git', 'push', '--set-upstream', 'origin', branch,
    ];
    _log(bp, '  \$ ${pushArgs.join(' ')}\n');
    final r = await Process.run(
      pushArgs.first,
      pushArgs.skip(1).toList(),
      workingDirectory: projectPath,
      environment: RuntimeEnvir.baseEnv,
    );
    if (r.stdout.toString().trim().isNotEmpty) {
      _log(bp, '${r.stdout}\n');
    }
    if (r.exitCode != 0) {
      _log(bp, 'ERRO: Push falhou:\n${r.stderr}\n');
      return false;
    }
    _log(bp, 'Push concluido (branch: $branch)\n');
    return true;
  }

  // ── GitHub Actions polling ────────────────────────────────────────────────

  Future<int?> _waitForRun({
    required String owner,
    required String repo,
    required String token,
    required BuildProvider buildProv,
    Duration timeout = const Duration(minutes: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    final since = DateTime.now().subtract(const Duration(minutes: 1));

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 8));
      if (_cancelled) return null;
      try {
        final url = Uri.parse(
            'https://api.github.com/repos/$owner/$repo/actions/runs'
            '?per_page=5&created=>=${since.toIso8601String()}');
        final resp = await http
            .get(url, headers: _headers(token))
            .timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          final data = jsonDecode(resp.body) as Map<String, dynamic>;
          final runs = (data['workflow_runs'] as List?) ?? [];
          if (runs.isNotEmpty) {
            return (runs.first['id'] as num).toInt();
          }
        }
      } catch (_) {}
      _log(buildProv, 'Aguardando run iniciar...\n');
    }
    return null;
  }

  Future<bool> _pollUntilDone({
    required String owner,
    required String repo,
    required int runId,
    required String token,
    required BuildProvider buildProv,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    int? jobId;
    var seenRawLines = 0;
    // stepStatus[n] = last known status string for step n
    final stepStatus = <int, String>{};
    // steps whose header line we already printed
    final headerPrinted = <int>{};

    while (DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(seconds: 3));
      if (_cancelled) {
        _log(buildProv, '\nCompilacao remota cancelada.\n');
        return false;
      }

      try {
        // ── 1. Resolve job ID ─────────────────────────────────────────────
        jobId ??= await _getFirstJobId(
            owner: owner, repo: repo, runId: runId, token: token);
        if (jobId == null) {
          _log(buildProv, 'Aguardando job ser atribuido...\n');
          continue;
        }

        // ── 2. Fetch job details (steps + status) ─────────────────────────
        final jobUrl = Uri.parse(
            'https://api.github.com/repos/$owner/$repo/actions/jobs/$jobId');
        final jobResp = await http
            .get(jobUrl, headers: _headers(token))
            .timeout(const Duration(seconds: 10));
        if (jobResp.statusCode != 200) continue;

        final jobData    = jsonDecode(jobResp.body) as Map<String, dynamic>;
        final status     = jobData['status']     as String? ?? '';
        final conclusion = jobData['conclusion'] as String?;
        final htmlUrl    = jobData['html_url']   as String? ?? '';
        final steps      = (jobData['steps'] as List?) ?? [];

        // ── 3. Show step headers as soon as they go in_progress ───────────
        var anyStepJustCompleted = false;
        for (final raw in steps) {
          final step    = raw as Map<String, dynamic>;
          final stepNum = (step['number'] as num).toInt();
          final name    = step['name']        as String? ?? '';
          final st      = step['status']      as String? ?? '';
          final prev    = stepStatus[stepNum];
          stepStatus[stepNum] = st;

          if (st == 'in_progress' && !headerPrinted.contains(stepNum)) {
            _log(buildProv, '\n$name\n${'─' * name.length.clamp(20, 60)}\n');
            headerPrinted.add(stepNum);
          } else if (st == 'completed' && prev == 'in_progress') {
            anyStepJustCompleted = true;
          }
        }

        // ── 4. Fetch raw logs and show new lines ───────────────────────────
        final rawLogs = await _fetchRawJobLogs(
            owner: owner, repo: repo, jobId: jobId, token: token);
        if (rawLogs != null && rawLogs.isNotEmpty) {
          final rawLines = rawLogs.split('\n');
          if (rawLines.length > seenRawLines) {
            final newChunk = rawLines.sublist(seenRawLines).join('\n');
            final formatted = _formatActionLogLines(newChunk);
            for (final line in formatted) {
              _log(buildProv, '$line\n');
            }
            seenRawLines = rawLines.length;
          }
        }

        // ── 5. Extra flush when a step just completed (logs may lag 1-2s) ──
        if (anyStepJustCompleted) {
          await Future.delayed(const Duration(seconds: 2));
          final flush = await _fetchRawJobLogs(
              owner: owner, repo: repo, jobId: jobId, token: token);
          if (flush != null && flush.isNotEmpty) {
            final rawLines = flush.split('\n');
            if (rawLines.length > seenRawLines) {
              final newChunk = rawLines.sublist(seenRawLines).join('\n');
              final formatted = _formatActionLogLines(newChunk);
              for (final line in formatted) {
                _log(buildProv, '$line\n');
              }
              seenRawLines = rawLines.length;
            }
          }
        }

        // ── 6. Done? Final drain ──────────────────────────────────────────
        if (status == 'completed') {
          for (var i = 0; i < 4; i++) {
            await Future.delayed(const Duration(seconds: 3));
            final flush = await _fetchRawJobLogs(
                owner: owner, repo: repo, jobId: jobId, token: token);
            if (flush == null) break;
            final rawLines = flush.split('\n');
            if (rawLines.length > seenRawLines) {
              final newChunk = rawLines.sublist(seenRawLines).join('\n');
              final formatted = _formatActionLogLines(newChunk);
              for (final line in formatted) {
                _log(buildProv, '$line\n');
              }
              seenRawLines = rawLines.length;
            } else {
              break;
            }
          }
          _log(buildProv, '\nCompilacao finalizada: $conclusion\n');
          if (htmlUrl.isNotEmpty) _log(buildProv, '   $htmlUrl\n');
          return conclusion == 'success';
        }
      } catch (_) {}
    }
    _log(buildProv, '\nERRO: Timeout aguardando compilacao\n');
    return false;
  }

  // ── GitHub Actions log helpers ────────────────────────────────────────────

  Future<int?> _getFirstJobId({
    required String owner,
    required String repo,
    required int runId,
    required String token,
  }) async {
    try {
      final url = Uri.parse(
          'https://api.github.com/repos/$owner/$repo/actions/runs/$runId/jobs');
      final resp = await http
          .get(url, headers: _headers(token))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final jobs = (data['jobs'] as List?) ?? [];
      if (jobs.isEmpty) return null;
      return (jobs.first['id'] as num).toInt();
    } catch (_) {
      return null;
    }
  }

  /// Fetches raw log text for a job.
  ///
  /// GitHub returns 302 → pre-signed storage URL. Dart's http package strips
  /// Authorization on cross-host redirects (RFC behaviour), so plain http.get()
  /// works. Manual redirect is kept as a fallback in case the auto path fails.
  Future<String?> _fetchRawJobLogs({
    required String owner,
    required String repo,
    required int jobId,
    required String token,
  }) async {
    final apiUrl = Uri.parse(
        'https://api.github.com/repos/$owner/$repo/actions/jobs/$jobId/logs');

    // ── Attempt 1: let http package follow the redirect automatically ────────
    try {
      final resp = await http
          .get(apiUrl, headers: _headers(token))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode == 200 && resp.body.isNotEmpty) return resp.body;
    } catch (_) {}

    // ── Attempt 2: manual redirect — fetch storage URL without auth header ───
    try {
      final client = http.Client();
      try {
        final req = http.Request('GET', apiUrl)
          ..headers.addAll(_headers(token))
          ..followRedirects = false;
        final initial = await client
            .send(req)
            .timeout(const Duration(seconds: 10));
        final location = initial.headers['location'];
        await initial.stream.drain<void>();
        if (location != null && location.isNotEmpty) {
          final logResp = await http
              .get(Uri.parse(location))
              .timeout(const Duration(seconds: 30));
          if (logResp.statusCode == 200 && logResp.body.isNotEmpty) {
            return logResp.body;
          }
        }
      } finally {
        client.close();
      }
    } catch (_) {}

    return null;
  }

  List<String> _formatActionLogLines(String rawChunk) {
    // Strip UTF-8 BOM that GitHub prepends to log files.
    final cleaned = rawChunk.replaceFirst('\uFEFF', '');
    final tsPattern   = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d+Z\s?');
    // ANSI escape codes: ESC [ ... m  (colors, bold, reset, etc.)
    final ansiPattern = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
    final result = <String>[];
    for (final raw in cleaned.split('\n')) {
      // Strip timestamp prefix, then ANSI codes.
      final line = raw
          .replaceFirst(tsPattern, '')
          .replaceAll(ansiPattern, '');
      if (line.startsWith('##[group]')) {
        final name = line.substring(9).trim();
        result.add('');
        result.add(name);
        result.add('─' * name.length.clamp(20, 60));
      } else if (line.startsWith('##[endgroup]') ||
                 line.startsWith('##[debug]')) {
        // skip
      } else if (line.startsWith('##[error]')) {
        result.add('ERRO: ${line.substring(9)}');
      } else if (line.startsWith('##[warning]')) {
        result.add('AVISO: ${line.substring(11)}');
      } else if (line.startsWith('##[command]')) {
        // Show the actual command being run (strip the marker).
        final cmd = line.substring(11).trim();
        if (cmd.isNotEmpty) result.add('> $cmd');
      } else if (line.trim().isNotEmpty) {
        result.add(line);
      }
    }
    return result;
  }

  // ── APK download ──────────────────────────────────────────────────────────

  Future<String?> _downloadApk({
    required String owner,
    required String repo,
    required int runId,
    required String token,
    required String projectPath,
    required BuildProvider buildProv,
  }) async {
    try {
      final artUrl = Uri.parse(
          'https://api.github.com/repos/$owner/$repo/actions/runs/$runId/artifacts');
      final artResp = await http
          .get(artUrl, headers: _headers(token))
          .timeout(const Duration(seconds: 10));
      if (artResp.statusCode != 200) {
        _log(buildProv,
            'ERRO: Nao foi possivel listar artefatos (${artResp.statusCode})\n');
        return null;
      }

      final data      = jsonDecode(artResp.body) as Map<String, dynamic>;
      final artifacts = (data['artifacts'] as List?) ?? [];
      final apkArt    = artifacts.firstWhere(
        (a) => (a['name'] as String).toLowerCase().contains('apk'),
        orElse: () => artifacts.isEmpty ? null : artifacts.first,
      );
      if (apkArt == null) {
        _log(buildProv, 'ERRO: Nenhum artefato APK encontrado\n');
        return null;
      }

      final artifactId = (apkArt['id'] as num).toInt();
      final dlUrl      = Uri.parse(
          'https://api.github.com/repos/$owner/$repo/actions/artifacts/$artifactId/zip');

      final tmp        = await getTemporaryDirectory();
      final zipFile    = File('${tmp.path}/fl_ide_artifact_$runId.zip');
      final extractDir = '${tmp.path}/fl_ide_artifact_$runId';

      // Stream the download so we can report progress in the build log.
      _log(buildProv, '\nBaixando APK...\n');
      final dlClient = http.Client();
      try {
        final req = http.Request('GET', dlUrl)
          ..headers.addAll(_headers(token));
        final streamed = await dlClient.send(req).timeout(const Duration(minutes: 5));
        if (streamed.statusCode != 200) {
          _log(buildProv,
              'ERRO: Falha ao baixar artefato (${streamed.statusCode})\n');
          return null;
        }

        final total   = streamed.contentLength ?? 0;
        var received  = 0;
        var lastPct   = -1;
        final sink    = zipFile.openWrite();
        try {
          await for (final chunk in streamed.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0) {
              final pct = received * 100 ~/ total;
              if (pct >= lastPct + 10) {
                lastPct = pct;
                final mb      = received / (1024 * 1024);
                final totalMb = total    / (1024 * 1024);
                _log(buildProv,
                    '${mb.toStringAsFixed(1)} MB / ${totalMb.toStringAsFixed(1)} MB ($pct%)\n');
              }
            }
          }
        } finally {
          await sink.flush();
          await sink.close();
        }

        if (total > 0) {
          final mb = received / (1024 * 1024);
          _log(buildProv, 'Download concluido: ${mb.toStringAsFixed(1)} MB\n');
        }
      } finally {
        dlClient.close();
      }
      await Directory(extractDir).create(recursive: true);

      final unzip = await Process.run(
        'unzip', ['-o', zipFile.path, '-d', extractDir],
        environment: RuntimeEnvir.baseEnv,
      );
      if (unzip.exitCode != 0) {
        _log(buildProv, 'ERRO: Falha ao extrair ZIP: ${unzip.stderr}\n');
        return null;
      }

      final apkFiles = Directory(extractDir)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.apk'))
          .toList();
      if (apkFiles.isEmpty) {
        _log(buildProv, 'ERRO: Nenhum APK encontrado no ZIP\n');
        return null;
      }

      final destPath = '$projectPath/fl_ide_remote_build.apk';
      await apkFiles.first.copy(destPath);

      await zipFile.delete().catchError((_) async => zipFile);
      final extractDirObj = Directory(extractDir);
      await extractDirObj
          .delete(recursive: true)
          .catchError((_) async => extractDirObj as FileSystemEntity);

      return destPath;
    } catch (e) {
      _log(buildProv, 'ERRO ao baixar APK: $e\n');
      return null;
    }
  }

  // ── Git low-level helpers ─────────────────────────────────────────────────

  Future<String?> _gitRemoteUrl(String projectPath) async {
    try {
      final r = await Process.run(
        'git', ['remote', 'get-url', 'origin'],
        workingDirectory: projectPath,
        environment: RuntimeEnvir.baseEnv,
      );
      if (r.exitCode != 0) return null;
      return (r.stdout as String).trim();
    } catch (_) {
      return null;
    }
  }

  Future<String> _currentBranch(String projectPath) async {
    try {
      final r = await Process.run(
        'git', ['rev-parse', '--abbrev-ref', 'HEAD'],
        workingDirectory: projectPath,
        environment: RuntimeEnvir.baseEnv,
      );
      final b = (r.stdout as String).trim();
      return b.isEmpty ? 'main' : b;
    } catch (_) {
      return 'main';
    }
  }

  Future<String> _gitConfig(String key, String projectPath,
      {required bool global}) async {
    try {
      final args = ['config', if (global) '--global' else '--local', key];
      final r = await Process.run(
        'git', args,
        workingDirectory: projectPath,
        environment: RuntimeEnvir.baseEnv,
      );
      return r.exitCode == 0 ? (r.stdout as String).trim() : '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _run(List<String> args, String workingDir) async {
    await Process.run(
      args.first,
      args.skip(1).toList(),
      workingDirectory: workingDir,
      environment: RuntimeEnvir.baseEnv,
    );
  }

  Future<void> _runLogged(
      List<String> args, String workingDir, BuildProvider bp) async {
    _log(bp, '  \$ ${args.join(' ')}\n');
    final r = await Process.run(
      args.first,
      args.skip(1).toList(),
      workingDirectory: workingDir,
      environment: RuntimeEnvir.baseEnv,
    );
    final out = (r.stdout as String).trim();
    if (out.isNotEmpty) _log(bp, '$out\n');
  }

  (String, String)? _parseGithubOwnerRepo(String url) {
    final m =
        RegExp(r'github\.com[/:]([^/]+)/([^/]+?)(?:\.git)?$').firstMatch(url);
    if (m != null) return (m.group(1)!, m.group(2)!);
    return null;
  }

  String _sanitizeRepoName(String name) =>
      name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9_.-]'), '-');

  // ── Content generators ────────────────────────────────────────────────────

  String _workflowYaml(SdkType sdk, [Map<String, String> versions = const {}]) {
    switch (sdk) {
      case SdkType.flutter:
        final flutterVersion = versions['flutter'] ?? '';
        final flutterSetup = flutterVersion.isNotEmpty
            ? '''      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '$flutterVersion'
          channel: 'stable'
          cache: true'''
            : '''      - uses: subosito/flutter-action@v2
        with:
          channel: 'stable'
          cache: true''';
        return '''
name: FL IDE Build (Flutter)
on:
  push:
    branches: [ main, master ]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      GRADLE_OPTS: "-Xmx4096m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8"
      JAVA_OPTS: "-Xmx4096m"
    steps:
      - uses: actions/checkout@v4
$flutterSetup
      - name: Configure Android SDK path
        run: |
          mkdir -p android
          echo "sdk.dir=\$ANDROID_HOME" > android/local.properties
          sed -i '/android\\.aapt2FromMavenOverride/d' android/gradle.properties 2>/dev/null || true
          grep -qxF 'org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m' android/gradle.properties 2>/dev/null || echo 'org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m' >> android/gradle.properties
      - run: flutter pub get
      - run: flutter build apk --release
      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: build/app/outputs/flutter-apk/app-release.apk
''';

      case SdkType.androidSdk:
        final javaVersion = versions['java'] ?? '17';
        return '''
name: FL IDE Build (Android)
on:
  push:
    branches: [ main, master ]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      GRADLE_OPTS: "-Xmx4096m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8"
      JAVA_OPTS: "-Xmx4096m"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '$javaVersion'
      - name: Configure Android SDK path
        run: |
          echo "sdk.dir=\$ANDROID_HOME" > local.properties
          sed -i '/android\\.aapt2FromMavenOverride/d' gradle.properties 2>/dev/null || true
          sed -i '/android\\.aapt2FromMavenOverride/d' app/build.gradle 2>/dev/null || true
          grep -qxF 'org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m' gradle.properties 2>/dev/null || echo 'org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m' >> gradle.properties
      - run: chmod +x ./gradlew
      - run: ./gradlew assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: app/build/outputs/apk/debug/app-debug.apk
''';

      case SdkType.reactNative:
        final nodeVersion = versions['node'] ?? '20';
        final javaVersion = versions['java'] ?? '17';
        return '''
name: FL IDE Build (React Native)
on:
  push:
    branches: [ main, master ]
jobs:
  build:
    runs-on: ubuntu-latest
    env:
      GRADLE_OPTS: "-Xmx4096m -XX:MaxMetaspaceSize=512m -Dfile.encoding=UTF-8"
      JAVA_OPTS: "-Xmx4096m"
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '$nodeVersion'
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: '$javaVersion'
      - run: npm install
      - name: Generate android/ if missing (Expo managed workflow)
        run: |
          if [ ! -d "android" ]; then
            echo "android/ not found — running expo prebuild..."
            npx expo prebuild --platform android --no-install || {
              echo "expo prebuild failed — android/ is required to build"
              exit 1
            }
          fi
      - name: Configure Android SDK path
        run: |
          mkdir -p android
          echo "sdk.dir=\$ANDROID_HOME" > android/local.properties
          sed -i '/android\\.aapt2FromMavenOverride/d' android/gradle.properties 2>/dev/null || true
          sed -i '/android\\.aapt2FromMavenOverride/d' android/app/build.gradle 2>/dev/null || true
          grep -qxF 'org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m' android/gradle.properties 2>/dev/null || echo 'org.gradle.jvmargs=-Xmx4096m -XX:MaxMetaspaceSize=512m' >> android/gradle.properties
          chmod +x android/gradlew
      - run: cd android && ./gradlew assembleDebug
      - uses: actions/upload-artifact@v4
        with:
          name: apk
          path: android/app/build/outputs/apk/debug/app-debug.apk
''';

      default:
        return '''
name: FL IDE Build
on:
  push:
    branches: [ main, master ]
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - run: echo "Build not configured for this SDK."
''';
    }
  }

  String _gitignoreFor(SdkType sdk) {
    switch (sdk) {
      case SdkType.flutter:
        return '''
# Flutter
.dart_tool/
.flutter-plugins
.flutter-plugins-dependencies
.packages
build/
*.iml
*.ipr
*.iws
.idea/
.vscode/

# Android — local paths must not be committed
android/local.properties
android/key.properties
android/.gradle/
**/android/**/gradle-wrapper.jar
''';
      case SdkType.androidSdk:
        return '''
# Android
*.iml
.gradle/
local.properties
.idea/
.DS_Store
build/
captures/
.externalNativeBuild/
.cxx/
''';
      case SdkType.reactNative:
        return '''
# React Native
node_modules/
.expo/
dist/
npm-debug.*
*.orig.*
web-build/

# Android — only build artifacts, NOT the android/ source tree
android/local.properties
android/key.properties
android/.gradle/
android/app/build/
android/build/

# iOS
ios/Pods/
ios/build/
''';
      default:
        return '''
# FL IDE
build/
dist/
.dart_tool/
node_modules/
__pycache__/
*.pyc
''';
    }
  }

  Map<String, String> _headers(String token) => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };
}
