import 'dart:async';
import 'dart:io';

import 'package:core/core.dart' show RuntimeEnvir;
import 'package:flutter/foundation.dart';

enum GitFileStatus { modified, added, deleted, renamed, untracked, conflicted, ignored }

class GitFileChange {
  final String path;
  final String? oldPath; // for renames
  final GitFileStatus status;
  final bool staged;

  const GitFileChange({
    required this.path,
    this.oldPath,
    required this.status,
    required this.staged,
  });

  String get displayName => path.split('/').last;

  String get statusLabel {
    switch (status) {
      case GitFileStatus.modified:    return 'M';
      case GitFileStatus.added:       return 'A';
      case GitFileStatus.deleted:     return 'D';
      case GitFileStatus.renamed:     return 'R';
      case GitFileStatus.untracked:   return 'U';
      case GitFileStatus.conflicted:  return 'C';
      case GitFileStatus.ignored:     return 'I';
    }
  }
}

class GitBranch {
  final String name;
  final bool isCurrent;
  final bool isRemote;
  const GitBranch({required this.name, required this.isCurrent, this.isRemote = false});
}

class GitProvider extends ChangeNotifier {
  final String projectPath;

  // State
  String _currentBranch = '';
  String _upstream = '';
  int _aheadCount = 0;
  int _behindCount = 0;
  List<GitFileChange> _staged = [];
  List<GitFileChange> _unstaged = [];
  List<GitBranch> _branches = [];
  bool _loading = false;
  String? _error;
  bool _isGitRepo = false;

  // Diff state
  String? _diffFilePath;
  String? _diffOriginalContent;
  String? _diffModifiedContent;
  bool _showDiff = false;

  // Commit message
  String _commitMessage = '';
  bool _pendingSync = false;

  Timer? _refreshTimer;

  /// Called with each git operation log line so the workspace can route it
  /// to the OUTPUT tab. Set by the workspace that owns this provider.
  void Function(String)? onOperationLog;

  /// Callback to reload the file tree after git init creates the `.git` dir.
  VoidCallback? onTreeRefreshNeeded;

  GitProvider({required this.projectPath}) {
    _init();
  }

  String get currentBranch => _currentBranch;
  String get upstream => _upstream;
  int get aheadCount => _aheadCount;
  int get behindCount => _behindCount;
  List<GitFileChange> get staged => List.unmodifiable(_staged);
  List<GitFileChange> get unstaged => List.unmodifiable(_unstaged);
  List<GitBranch> get branches => List.unmodifiable(_branches);
  bool get loading => _loading;
  String? get error => _error;
  bool get isGitRepo => _isGitRepo;
  bool get showDiff => _showDiff;
  String? get diffFilePath => _diffFilePath;
  String? get diffOriginalContent => _diffOriginalContent;
  String? get diffModifiedContent => _diffModifiedContent;
  String get commitMessage => _commitMessage;
  bool get pendingSync => _pendingSync;
  int get totalChanges => _staged.length + _unstaged.length;

  void setCommitMessage(String msg) {
    _commitMessage = msg;
    notifyListeners();
  }

  Future<void> _init() async {
    _isGitRepo = await _checkIsGitRepo();
    if (_isGitRepo) {
      await refresh();
      _startTimer();
    }
    notifyListeners();
  }

  void _startTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  /// Runs `git init` in the project directory and activates the provider.
  Future<String?> initRepo() async {
    final r = await _run(['init']);
    if (r.exitCode != 0) return r.stderr.trim();
    _isGitRepo = true;
    notifyListeners();
    await refresh();
    _startTimer();
    onTreeRefreshNeeded?.call(); // reload file tree so .git stays hidden
    return null;
  }

  Future<bool> _checkIsGitRepo() async {
    try {
      final result = await _run(['rev-parse', '--is-inside-work-tree']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await Future.wait([
        _fetchBranch(),
        _fetchStatus(),
        _fetchBranches(),
      ]);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchBranch() async {
    try {
      final r = await _run(['branch', '--show-current']);
      _currentBranch = r.stdout.toString().trim();

      final revList = await _run([
        'rev-list', '--left-right', '--count', 'HEAD...@{upstream}',
      ]);
      if (revList.exitCode == 0) {
        final parts = revList.stdout.trim().split(RegExp(r'\s+'));
        if (parts.length == 2) {
          _aheadCount = int.tryParse(parts[0]) ?? 0;
          _behindCount = int.tryParse(parts[1]) ?? 0;
        }
      }
      final upstreamR = await _run([
        'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}',
      ]);
      _upstream = upstreamR.exitCode == 0 ? upstreamR.stdout.trim() : '';
    } catch (_) {}
  }

  Future<void> _fetchStatus() async {
    final r = await _run(['status', '--porcelain=v1']);
    if (r.exitCode != 0) return;

    final staged = <GitFileChange>[];
    final unstaged = <GitFileChange>[];

    for (final line in r.stdout.toString().split('\n')) {
      if (line.length < 2) continue;
      final x = line[0]; // staged status
      final y = line[1]; // unstaged status
      final rest = line.substring(3).trim();

      // Handle rename: "old -> new"
      String filePath = rest;
      String? oldPath;
      if (rest.contains(' -> ')) {
        final parts = rest.split(' -> ');
        oldPath = parts[0].trim();
        filePath = parts[1].trim();
      }

      if (x != ' ' && x != '?') {
        staged.add(GitFileChange(
          path: filePath,
          oldPath: oldPath,
          status: _parseStatus(x),
          staged: true,
        ));
      }
      if (y != ' ' && y != '?') {
        unstaged.add(GitFileChange(
          path: filePath,
          status: _parseStatus(y),
          staged: false,
        ));
      } else if (x == '?' && y == '?') {
        unstaged.add(GitFileChange(
          path: filePath,
          status: GitFileStatus.untracked,
          staged: false,
        ));
      }
    }

    // Filter out files that are ignored by .gitignore so they don't clutter
    // the panel. git ls-files lists every ignored untracked path.
    final ignoredSet = await _fetchIgnoredPaths();
    _staged = staged;
    _unstaged = unstaged.where((f) => !ignoredSet.contains(f.path)).toList();
  }

  Future<Set<String>> _fetchIgnoredPaths() async {
    try {
      final r = await _run([
        'ls-files', '--others', '--ignored', '--exclude-standard',
      ]);
      if (r.exitCode != 0) return {};
      return r.stdout.toString()
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet();
    } catch (_) {
      return {};
    }
  }

  Future<void> _fetchBranches() async {
    final r = await _run(['branch', '-a', '--format=%(refname:short) %(HEAD)']);
    if (r.exitCode != 0) return;
    _branches = r.stdout.toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .map((l) {
          final isCurrent = l.endsWith(' *');
          final name = l.replaceAll(' *', '').trim();
          return GitBranch(
            name: name,
            isCurrent: isCurrent,
            isRemote: name.startsWith('remotes/'),
          );
        })
        .toList();
  }

  GitFileStatus _parseStatus(String code) {
    switch (code) {
      case 'M': return GitFileStatus.modified;
      case 'A': return GitFileStatus.added;
      case 'D': return GitFileStatus.deleted;
      case 'R': return GitFileStatus.renamed;
      case 'U': return GitFileStatus.conflicted;
      case '!': return GitFileStatus.ignored;
      default:  return GitFileStatus.untracked;
    }
  }

  // ── Git operations ──────────────────────────────────────────────────────────

  Future<void> stageFile(String filePath) async {
    await _run(['add', filePath]);
    await _fetchStatus();
    notifyListeners();
  }

  Future<void> stageAll() async {
    await _run(['add', '-A']);
    await _fetchStatus();
    notifyListeners();
  }

  Future<void> unstageFile(String filePath) async {
    await _run(['reset', 'HEAD', filePath]);
    await _fetchStatus();
    notifyListeners();
  }

  Future<void> unstageAll() async {
    await _run(['reset', 'HEAD']);
    await _fetchStatus();
    notifyListeners();
  }

  Future<void> discardFile(String filePath) async {
    await _run(['checkout', '--', filePath]);
    await _fetchStatus();
    notifyListeners();
  }

  Future<String?> commit() async {
    if (_commitMessage.trim().isEmpty) return 'Commit message cannot be empty';
    // If nothing staged, stage everything first (VS Code behaviour)
    if (_staged.isEmpty && _unstaged.isNotEmpty) await stageAll();
    final r = await _run(['commit', '-m', _commitMessage.trim()]);
    if (r.exitCode != 0) return r.stderr.trim();
    _commitMessage = '';
    _pendingSync = true;
    await refresh();
    return null;
  }

  void clearPendingSync() {
    _pendingSync = false;
    notifyListeners();
  }

  /// Returns true if at least one remote is configured.
  Future<bool> hasRemote() async {
    final r = await _run(['remote']);
    return r.exitCode == 0 && r.stdout.toString().trim().isNotEmpty;
  }

  /// Adds a remote (default name: origin).
  Future<String?> addRemote(String url, {String name = 'origin'}) async {
    // Remove existing origin if present so we can replace it cleanly.
    await _run(['remote', 'remove', name]);
    final r = await _run(['remote', 'add', name, url]);
    if (r.exitCode != 0) return r.stderr.toString().trim();
    await _fetchBranch();
    notifyListeners();
    return null;
  }

  Future<String?> push() async {
    onOperationLog?.call('[git] push → ${_upstream.isNotEmpty ? _upstream : "origin"}\n');
    var r = await _run(['push']);
    if (r.stdout.toString().trim().isNotEmpty) onOperationLog?.call(r.stdout.toString());
    if (r.stderr.toString().trim().isNotEmpty) onOperationLog?.call(r.stderr.toString());
    if (r.exitCode != 0) {
      final stderr = r.stderr.toString();
      // No remote at all → caller must configure one first.
      if (stderr.contains('No configured push destination') ||
          stderr.contains('no remote')) {
        return kNoRemoteError;
      }
      // Branch exists but has no upstream tracking → set it now.
      if (stderr.contains('--set-upstream') ||
          stderr.contains('no upstream') ||
          stderr.contains('has no upstream')) {
        r = await _run(['push', '--set-upstream', 'origin', _currentBranch]);
      }
      if (r.exitCode != 0) return r.stderr.toString().trim();
    }
    _pendingSync = false;
    await _fetchBranch();
    notifyListeners();
    return null;
  }

  static const String kNoRemoteError = '__no_remote__';

  Future<String?> pull() async {
    onOperationLog?.call('[git] pull\n');
    final r = await _run(['pull']);
    if (r.stdout.toString().trim().isNotEmpty) onOperationLog?.call(r.stdout.toString());
    if (r.stderr.toString().trim().isNotEmpty) onOperationLog?.call(r.stderr.toString());
    if (r.exitCode != 0) return r.stderr.trim();
    _pendingSync = false;
    await refresh();
    return null;
  }

  Future<String?> fetch() async {
    onOperationLog?.call('[git] fetch --all\n');
    final r = await _run(['fetch', '--all']);
    if (r.stdout.toString().trim().isNotEmpty) onOperationLog?.call(r.stdout.toString());
    if (r.stderr.toString().trim().isNotEmpty) onOperationLog?.call(r.stderr.toString());
    if (r.exitCode != 0) return r.stderr.trim();
    await _fetchBranch();
    notifyListeners();
    return null;
  }

  Future<String?> checkout(String branch) async {
    final r = await _run(['checkout', branch]);
    if (r.exitCode != 0) return r.stderr.trim();
    await refresh();
    return null;
  }

  Future<String?> createBranch(String name) async {
    final r = await _run(['checkout', '-b', name]);
    if (r.exitCode != 0) return r.stderr.trim();
    await refresh();
    return null;
  }

  // ── Diff ───────────────────────────────────────────────────────────────────

  Future<void> openDiff(String filePath, {bool staged = false}) async {
    _diffFilePath = filePath;
    _showDiff = true;

    final fullPath = '$projectPath/$filePath';

    // Original: HEAD version
    final headR = await _run(['show', 'HEAD:$filePath']);
    _diffOriginalContent = headR.exitCode == 0 ? headR.stdout : '';

    // Modified: current file or staged version
    if (staged) {
      final stagedR = await _run(['show', ':$filePath']);
      _diffModifiedContent = stagedR.exitCode == 0 ? stagedR.stdout : '';
    } else {
      try {
        _diffModifiedContent = await File(fullPath).readAsString();
      } catch (_) {
        _diffModifiedContent = '';
      }
    }

    notifyListeners();
  }

  void closeDiff() {
    _showDiff = false;
    _diffFilePath = null;
    _diffOriginalContent = null;
    _diffModifiedContent = null;
    notifyListeners();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<ProcessResult> _run(List<String> args) async {
    return Process.run(
      'git', args,
      workingDirectory: projectPath,
      environment: RuntimeEnvir.baseEnv,
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}
