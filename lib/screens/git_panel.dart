import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../providers/git_provider.dart';
import '../providers/settings_provider.dart';

// ════════════════════════════════════════════════════════════════════════════
//  Git Panel — VS Code Source Control side-panel
// ════════════════════════════════════════════════════════════════════════════

class GitPanel extends StatefulWidget {
  final VoidCallback? onClose;
  const GitPanel({super.key, this.onClose});

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  final _commitCtrl = TextEditingController();
  bool _stagedExpanded = true;
  bool _unstagedExpanded = true;
  bool _branchesExpanded = false;

  @override
  void initState() {
    super.initState();
    final git = context.read<GitProvider>();
    _commitCtrl.text = git.commitMessage;
    _commitCtrl.addListener(() {
      context.read<GitProvider>().setCommitMessage(_commitCtrl.text);
    });
  }

  @override
  void dispose() {
    _commitCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final git = context.watch<GitProvider>();

    if (!git.isGitRepo) {
      return _NotAGitRepo(projectPath: git.projectPath);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(git: git),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _CommitSection(
                ctrl: _commitCtrl,
                git: git,
                onCommit: () => _doCommit(context, git),
                onSync: () => _doSync(context, git),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              if (git.staged.isNotEmpty)
                _Section(
                  label: 'STAGED CHANGES',
                  count: git.staged.length,
                  expanded: _stagedExpanded,
                  onToggle: () => setState(() => _stagedExpanded = !_stagedExpanded),
                  trailing: _IconBtn(
                    icon: Icons.remove_circle_outline,
                    tooltip: 'Unstage All',
                    onTap: git.unstageAll,
                  ),
                  children: _stagedExpanded
                      ? git.staged.map((f) => _FileRow(
                            file: f,
                            onAction1: () => git.unstageFile(f.path),
                            action1Icon: Icons.remove_circle_outline,
                            action1Tooltip: 'Unstage',
                            onOpen: () {
                              git.openDiff(f.path, staged: true);
                              widget.onClose?.call();
                            },
                          )).toList()
                      : [],
                ),
              _Section(
                label: 'CHANGES',
                count: git.unstaged.length,
                expanded: _unstagedExpanded,
                onToggle: () => setState(() => _unstagedExpanded = !_unstagedExpanded),
                trailing: _IconBtn(
                  icon: Icons.add_circle_outline,
                  tooltip: 'Stage All',
                  onTap: git.stageAll,
                ),
                children: _unstagedExpanded
                    ? git.unstaged.map((f) => _FileRow(
                          file: f,
                          onAction1: () => git.stageFile(f.path),
                          action1Icon: Icons.add_circle_outline,
                          action1Tooltip: 'Stage',
                          onAction2: f.status != GitFileStatus.untracked
                              ? () => _confirmDiscard(context, git, f)
                              : null,
                          action2Icon: Icons.undo,
                          action2Tooltip: 'Discard Changes',
                          onOpen: f.status != GitFileStatus.untracked
                              ? () {
                                  git.openDiff(f.path);
                                  widget.onClose?.call();
                                }
                              : null,
                        )).toList()
                    : [],
              ),
              _Section(
                label: 'BRANCHES',
                count: git.branches.where((b) => !b.isRemote).length,
                expanded: _branchesExpanded,
                onToggle: () => setState(() => _branchesExpanded = !_branchesExpanded),
                trailing: _IconBtn(
                  icon: Icons.add,
                  tooltip: 'New Branch',
                  onTap: () => _newBranch(context, git),
                ),
                children: _branchesExpanded
                    ? git.branches
                        .where((b) => !b.isRemote)
                        .map((b) => _BranchRow(
                              branch: b,
                              onCheckout: () => _checkout(context, git, b),
                            ))
                        .toList()
                    : [],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _doSync(BuildContext context, GitProvider git) async {
    String? err;
    if (git.behindCount > 0) err = await git.pull();
    if (err != null && context.mounted) { _showError(context, err); return; }
    err = await git.push();
    if (!context.mounted) return;
    if (err == GitProvider.kNoRemoteError) {
      await _showAddRemoteDialog(context, git);
    } else if (err != null) {
      _showError(context, err);
    }
  }

  Future<void> _showAddRemoteDialog(BuildContext context, GitProvider git) async {
    final settings = context.read<SettingsProvider>();
    final token = settings.githubToken;

    if (token.isEmpty) {
      _showError(context,
          'GitHub token not configured. Go to Settings → Remote Git Build to add your token.');
      return;
    }

    // Fetch GitHub username from the token.
    String githubUser;
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/user'),
        headers: {'Authorization': 'Bearer $token', 'Accept': 'application/vnd.github+json'},
      );
      if (res.statusCode != 200) {
        if (context.mounted) _showError(context, 'GitHub auth failed: ${res.statusCode}');
        return;
      }
      githubUser = (jsonDecode(res.body) as Map<String, dynamic>)['login'] as String;
    } catch (e) {
      if (context.mounted) _showError(context, 'GitHub error: $e');
      return;
    }

    if (!context.mounted) return;

    // Default repo name = last segment of project path.
    final defaultName = git.projectPath.split(RegExp(r'[/\\]')).last;

    final result = await showDialog<({String repoName, bool isPrivate})>(
      context: context,
      builder: (ctx) => _PublishBranchDialog(
        branchName: git.currentBranch,
        defaultRepoName: defaultName,
        githubUser: githubUser,
      ),
    );
    if (result == null || !context.mounted) return;

    // Create repository on GitHub.
    try {
      final res = await http.post(
        Uri.parse('https://api.github.com/user/repos'),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'name': result.repoName,
          'private': result.isPrivate,
          'auto_init': false,
        }),
      );
      if (res.statusCode != 201) {
        if (context.mounted) {
          final msg = (jsonDecode(res.body) as Map<String, dynamic>)['message'] ?? res.statusCode;
          _showError(context, 'Failed to create repo: $msg');
        }
        return;
      }
      final cloneUrl =
          (jsonDecode(res.body) as Map<String, dynamic>)['clone_url'] as String;
      if (!context.mounted) return;
      final addErr = await git.addRemote(cloneUrl);
      if (!context.mounted) return;
      if (addErr != null) { _showError(context, addErr); return; }
      final pushErr = await git.push();
      if (pushErr != null && context.mounted) _showError(context, pushErr);
    } catch (e) {
      if (context.mounted) _showError(context, 'GitHub error: $e');
    }
  }

  Future<void> _doCommit(BuildContext context, GitProvider git) async {
    final err = await git.commit();
    if (!context.mounted) return;
    if (err != null) {
      _showError(context, err);
    } else {
      _commitCtrl.clear();
    }
  }

  Future<void> _confirmDiscard(BuildContext context, GitProvider git, GitFileChange f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Discard Changes'),
        content: Text('Discard changes to "${f.displayName}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Discard')),
        ],
      ),
    );
    if (ok == true && context.mounted) await git.discardFile(f.path);
  }

  Future<void> _newBranch(BuildContext context, GitProvider git) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New Branch'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Branch name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('Create')),
        ],
      ),
    );
    if (name != null && name.isNotEmpty && context.mounted) {
      final err = await git.createBranch(name);
      if (err != null && context.mounted) _showError(context, err);
    }
  }

  Future<void> _checkout(BuildContext context, GitProvider git, GitBranch branch) async {
    if (branch.isCurrent) return;
    final err = await git.checkout(branch.name);
    if (err != null && context.mounted) _showError(context, err);
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final GitProvider git;
  const _Header({required this.git});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.source_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'SOURCE CONTROL',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (git.loading)
            SizedBox(
              width: 16, height: 16,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
            )
          else
            _IconBtn(icon: Icons.refresh, tooltip: 'Refresh', onTap: git.refresh),
          if (git.upstream.isNotEmpty)
            _SyncChip(aheadCount: git.aheadCount, behindCount: git.behindCount, git: git),
        ],
      ),
    );
  }
}

class _SyncChip extends StatelessWidget {
  final int aheadCount;
  final int behindCount;
  final GitProvider git;
  const _SyncChip({required this.aheadCount, required this.behindCount, required this.git});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => _sync(context),
      icon: const Icon(Icons.sync, size: 14),
      label: Text('$aheadCount↑ $behindCount↓', style: const TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Future<void> _sync(BuildContext context) async {
    final g = context.read<GitProvider>();
    String? err;
    if (g.behindCount > 0) err = await g.pull();
    if (err == null && g.aheadCount > 0) err = await g.push();
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
  }
}

// ── Commit section ────────────────────────────────────────────────────────────

class _CommitSection extends StatelessWidget {
  final TextEditingController ctrl;
  final GitProvider git;
  final VoidCallback onCommit;
  final VoidCallback onSync;

  const _CommitSection({required this.ctrl, required this.git, required this.onCommit, required this.onSync});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                git.currentBranch.isEmpty ? '(no branch)' : git.currentBranch,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            maxLines: 3,
            minLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Message (commit)',
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          if (git.pendingSync) ...[
            FilledButton.icon(
              onPressed: onSync,
              icon: const Icon(Icons.sync, size: 16),
              label: Text(
                git.upstream.isNotEmpty ? 'Sync Changes' : 'Publish Branch',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(36),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: git.clearPendingSync,
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Continue Editing'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(34),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
          ] else
            FilledButton.icon(
              onPressed: (git.staged.isNotEmpty || git.unstaged.isNotEmpty) ? onCommit : null,
              icon: const Icon(Icons.check, size: 16),
              label: Text(
                git.staged.isNotEmpty
                    ? 'Commit (${git.staged.length})'
                    : 'Commit All (${git.unstaged.length})',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(36),
                textStyle: const TextStyle(fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Section ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget? trailing;
  final List<Widget> children;

  const _Section({
    required this.label,
    required this.count,
    required this.expanded,
    required this.onToggle,
    this.trailing,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16, color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    '$label ($count)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

// ── File row ──────────────────────────────────────────────────────────────────

class _FileRow extends StatefulWidget {
  final GitFileChange file;
  final VoidCallback onAction1;
  final IconData action1Icon;
  final String action1Tooltip;
  final VoidCallback? onAction2;
  final IconData? action2Icon;
  final String? action2Tooltip;
  final VoidCallback? onOpen;

  const _FileRow({
    required this.file,
    required this.onAction1,
    required this.action1Icon,
    required this.action1Tooltip,
    this.onAction2,
    this.action2Icon,
    this.action2Tooltip,
    this.onOpen,
  });

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(cs, widget.file.status);
    final dirPart = widget.file.path.contains('/')
        ? widget.file.path.substring(0, widget.file.path.lastIndexOf('/'))
        : '';

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onOpen,
        child: Container(
          color: _hovered ? cs.surfaceContainerHighest.withValues(alpha: 0.5) : null,
          padding: const EdgeInsets.only(left: 28, right: 4),
          height: 28,
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      widget.file.displayName,
                      style: TextStyle(fontSize: 13, color: cs.onSurface),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dirPart.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          dirPart,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.onAction2 != null)
                _IconBtn(
                  icon: widget.action2Icon!,
                  tooltip: widget.action2Tooltip!,
                  onTap: widget.onAction2!,
                ),
              _IconBtn(
                icon: widget.action1Icon,
                tooltip: widget.action1Tooltip,
                onTap: widget.onAction1,
              ),
              SizedBox(
                width: 18,
                child: Text(
                  widget.file.statusLabel,
                  style: TextStyle(
                    color: statusColor, fontSize: 12, fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(ColorScheme cs, GitFileStatus s) {
    switch (s) {
      case GitFileStatus.added:      return Colors.green;
      case GitFileStatus.deleted:    return cs.error;
      case GitFileStatus.modified:   return Colors.orange;
      case GitFileStatus.renamed:    return Colors.blue;
      case GitFileStatus.conflicted: return Colors.red;
      case GitFileStatus.untracked:  return Colors.green;
      case GitFileStatus.ignored:    return cs.onSurfaceVariant;
    }
  }
}

// ── Branch row ────────────────────────────────────────────────────────────────

class _BranchRow extends StatelessWidget {
  final GitBranch branch;
  final VoidCallback onCheckout;

  const _BranchRow({required this.branch, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onCheckout,
      child: Padding(
        padding: const EdgeInsets.only(left: 28, right: 12, top: 4, bottom: 4),
        child: Row(
          children: [
            if (branch.isCurrent)
              Icon(Icons.check, size: 14, color: cs.primary)
            else
              const SizedBox(width: 14),
            const SizedBox(width: 4),
            Icon(Icons.call_split, size: 13,
                color: branch.isCurrent ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              branch.name,
              style: TextStyle(
                fontSize: 13,
                color: branch.isCurrent ? cs.primary : cs.onSurface,
                fontWeight: branch.isCurrent ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Not a git repo ────────────────────────────────────────────────────────────

class _NotAGitRepo extends StatelessWidget {
  final String projectPath;
  const _NotAGitRepo({required this.projectPath});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 48,
            alignment: Alignment.centerLeft,
            child: Text(
              'SOURCE CONTROL',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No Git repository found in this project.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _initRepo(context),
            icon: const Icon(Icons.source_outlined, size: 16),
            label: const Text('Initialize Repository'),
          ),
        ],
      ),
    );
  }

  Future<void> _initRepo(BuildContext context) async {
    final git = context.read<GitProvider>();
    final err = await git.initRepo();
    if (err != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// ── Shared icon button ────────────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
//  Diff view — split screen with syntax highlighting + line colours
// ════════════════════════════════════════════════════════════════════════════

/// A line in the diff result.
enum _DiffKind { unchanged, removed, added }

class _DiffLine {
  final String text;
  final _DiffKind kind;
  final int lineNo; // 1-based line number in the respective file
  const _DiffLine(this.text, this.kind, this.lineNo);
}

/// Myers-like LCS-based line diff.
/// Returns two parallel lists: one for the original panel, one for the modified panel.
/// Null entries are placeholder "empty" rows to keep panels aligned.
class _Differ {
  static ({List<_DiffLine> orig, List<_DiffLine> mod}) compute(
      List<String> a, List<String> b) {
    // LCS table
    final m = a.length, n = b.length;
    final dp = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (int i = m - 1; i >= 0; i--) {
      for (int j = n - 1; j >= 0; j--) {
        dp[i][j] = a[i] == b[j]
            ? dp[i + 1][j + 1] + 1
            : dp[i + 1][j] >= dp[i][j + 1]
                ? dp[i + 1][j]
                : dp[i][j + 1];
      }
    }

    final orig = <_DiffLine>[];
    final mod = <_DiffLine>[];
    int i = 0, j = 0, ai = 1, bi = 1;

    while (i < m && j < n) {
      if (a[i] == b[j]) {
        orig.add(_DiffLine(a[i], _DiffKind.unchanged, ai++));
        mod.add(_DiffLine(b[j], _DiffKind.unchanged, bi++));
        i++; j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        orig.add(_DiffLine(a[i], _DiffKind.removed, ai++));
        mod.add(_DiffLine('', _DiffKind.removed, 0)); // placeholder
        i++;
      } else {
        orig.add(_DiffLine('', _DiffKind.added, 0)); // placeholder
        mod.add(_DiffLine(b[j], _DiffKind.added, bi++));
        j++;
      }
    }
    while (i < m) {
      orig.add(_DiffLine(a[i], _DiffKind.removed, ai++));
      mod.add(_DiffLine('', _DiffKind.removed, 0));
      i++;
    }
    while (j < n) {
      orig.add(_DiffLine('', _DiffKind.added, 0));
      mod.add(_DiffLine(b[j], _DiffKind.added, bi++));
      j++;
    }
    return (orig: orig, mod: mod);
  }
}

/// Simple regex-based syntax highlighter.
class _Highlighter {
  static final Map<String, List<({RegExp re, Color Function(ColorScheme) color})>> _rules = {
    'dart': _dartRules,
    'kt':   _kotlinRules,
    'kts':  _kotlinRules,
    'java': _javaRules,
    'js':   _jsRules,
    'ts':   _jsRules,
    'tsx':  _jsRules,
    'jsx':  _jsRules,
    'xml':  _xmlRules,
    'gradle': _kotlinRules,
    'yaml': _yamlRules,
    'json': _jsonRules,
    'py':   _pythonRules,
    'swift': _swiftRules,
  };

  static const _dartKeywords =
      r'\b(abstract|as|assert|async|await|base|break|case|catch|class|const|'
      r'continue|covariant|default|deferred|do|dynamic|else|enum|export|'
      r'extends|extension|external|factory|false|final|finally|for|'
      r'Function|get|hide|if|implements|import|in|interface|is|late|'
      r'library|mixin|new|null|on|operator|part|required|rethrow|return|'
      r'sealed|set|show|static|super|switch|sync|this|throw|true|try|'
      r'typedef|var|void|while|with|yield)\b';

  static const _javaKeywords =
      r'\b(abstract|assert|boolean|break|byte|case|catch|char|class|const|'
      r'continue|default|do|double|else|enum|extends|final|finally|float|'
      r'for|goto|if|implements|import|instanceof|int|interface|long|native|'
      r'new|null|package|private|protected|public|return|short|static|'
      r'strictfp|super|switch|synchronized|this|throw|throws|transient|'
      r'true|false|try|void|volatile|while)\b';

  static const _jsKeywords =
      r'\b(async|await|break|case|catch|class|const|continue|debugger|'
      r'default|delete|do|else|export|extends|false|finally|for|from|'
      r'function|if|import|in|instanceof|let|new|null|of|return|static|'
      r'super|switch|this|throw|true|try|type|typeof|undefined|var|'
      r'void|while|with|yield|interface|implements|declare)\b';

  static const _swiftKeywords =
      r'\b(associatedtype|class|deinit|enum|extension|fileprivate|func|import|'
      r'init|inout|internal|let|open|operator|private|precedencegroup|'
      r'protocol|public|rethrows|static|struct|subscript|typealias|var|'
      r'break|case|catch|continue|default|defer|do|else|fallthrough|for|'
      r'guard|if|in|nil|repeat|return|self|super|switch|throw|throws|true|'
      r'false|try|where|while|as|is|some|any)\b';

  // String pattern: matches "..." — using double-quote raw strings to avoid
  // the Dart raw-string limitation where \' inside r'...' closes the literal.
  static final _reString  = RegExp(r'"(?:[^"\\]|\\.)*"');
  static final _reComment = RegExp(r'//.*');
  static final _reBlockCmt= RegExp(r'/\*.*?\*/', dotAll: true);
  static final _reNumber  = RegExp(r'\b\d+\.?\d*\b');
  static final _reHash    = RegExp(r'#.*');

  static List<({RegExp re, Color Function(ColorScheme) color})> get _dartRules => [
    (re: RegExp(_dartKeywords),  color: (cs) => cs.primary),
    (re: _reString,              color: (cs) => Colors.orange.shade300),
    (re: _reComment,             color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reBlockCmt,            color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reNumber,              color: (cs) => Colors.lightBlue.shade300),
  ];

  static final _reKtKeywords = RegExp(
    r'\b(abstract|actual|annotation|as|break|by|catch|class|companion|const|'
    r'constructor|continue|crossinline|data|delegate|do|dynamic|else|enum|expect|'
    r'external|false|final|finally|for|fun|get|if|import|in|infix|init|inline|'
    r'inner|interface|internal|is|it|lateinit|noinline|null|object|open|operator|'
    r'out|override|package|private|protected|public|reified|return|sealed|set|'
    r'super|suspend|tailrec|this|throw|true|try|typealias|typeof|val|var|vararg|'
    r'when|where|while)\b',
  );

  static final _rePyKeywords = RegExp(
    r'\b(False|None|True|and|as|assert|async|await|break|class|continue|'
    r'def|del|elif|else|except|finally|for|from|global|if|import|in|is|'
    r'lambda|nonlocal|not|or|pass|raise|return|try|while|with|yield)\b',
  );

  static List<({RegExp re, Color Function(ColorScheme) color})> get _kotlinRules => [
    (re: _reKtKeywords, color: (cs) => cs.primary),
    (re: _reString,     color: (cs) => Colors.orange.shade300),
    (re: _reComment,    color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reNumber,     color: (cs) => Colors.lightBlue.shade300),
  ];

  static List<({RegExp re, Color Function(ColorScheme) color})> get _javaRules => [
    (re: RegExp(_javaKeywords), color: (cs) => cs.primary),
    (re: _reString,             color: (cs) => Colors.orange.shade300),
    (re: _reComment,            color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reNumber,             color: (cs) => Colors.lightBlue.shade300),
  ];

  static final _reJsString = RegExp(r'"(?:[^"\\]|\\.)*"|`(?:[^`\\]|\\.)*`');

  static List<({RegExp re, Color Function(ColorScheme) color})> get _jsRules => [
    (re: RegExp(_jsKeywords), color: (cs) => cs.primary),
    (re: _reJsString,         color: (cs) => Colors.orange.shade300),
    (re: _reComment,          color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reNumber,           color: (cs) => Colors.lightBlue.shade300),
  ];

  static List<({RegExp re, Color Function(ColorScheme) color})> get _xmlRules => [
    (re: RegExp(r'<[/?!]?[\w:.-]+'),   color: (cs) => Colors.blue.shade300),
    (re: RegExp(r'[/?]?>'),             color: (cs) => Colors.blue.shade300),
    (re: RegExp(r'[\w:.-]+='),          color: (cs) => cs.tertiary),
    (re: _reString,                     color: (cs) => Colors.orange.shade300),
    (re: RegExp(r'<!--.*?-->', dotAll: true),
        color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
  ];

  static List<({RegExp re, Color Function(ColorScheme) color})> get _yamlRules => [
    (re: RegExp(r'^[\w-]+(?=\s*:)', multiLine: true), color: (cs) => cs.primary),
    (re: _reString,  color: (cs) => Colors.orange.shade300),
    (re: _reHash,    color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: RegExp(r'\b(true|false|null)\b'), color: (cs) => Colors.lightBlue.shade300),
    (re: _reNumber,  color: (cs) => Colors.lightBlue.shade300),
  ];

  static List<({RegExp re, Color Function(ColorScheme) color})> get _jsonRules => [
    (re: RegExp(r'"(?:[^"\\]|\\.)*"\s*:'), color: (cs) => cs.primary),
    (re: RegExp(r':\s*"(?:[^"\\]|\\.)*"'), color: (cs) => Colors.orange.shade300),
    (re: RegExp(r'\b(true|false|null)\b'),  color: (cs) => Colors.lightBlue.shade300),
    (re: RegExp(r'\b-?\d+\.?\d*(?:[eE][+-]?\d+)?\b'),
        color: (cs) => Colors.lightBlue.shade300),
  ];

  static List<({RegExp re, Color Function(ColorScheme) color})> get _pythonRules => [
    (re: _rePyKeywords, color: (cs) => cs.primary),
    (re: _reString,     color: (cs) => Colors.orange.shade300),
    (re: _reHash,       color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reNumber,     color: (cs) => Colors.lightBlue.shade300),
  ];

  static List<({RegExp re, Color Function(ColorScheme) color})> get _swiftRules => [
    (re: RegExp(_swiftKeywords), color: (cs) => cs.primary),
    (re: _reString,              color: (cs) => Colors.orange.shade300),
    (re: _reComment,             color: (cs) => cs.onSurfaceVariant.withValues(alpha: 0.7)),
    (re: _reNumber,              color: (cs) => Colors.lightBlue.shade300),
  ];

  /// Returns a list of [TextSpan]s for one line of code.
  static List<TextSpan> highlight(String line, String ext, ColorScheme cs, Color baseColor) {
    final rules = _rules[ext.toLowerCase()];
    if (rules == null || line.isEmpty) {
      return [TextSpan(text: line, style: TextStyle(color: baseColor))];
    }

    // Build a list of (start, end, color) for every match, then fill gaps.
    final spans = <({int start, int end, Color color})>[];
    for (final rule in rules) {
      for (final m in rule.re.allMatches(line)) {
        spans.add((start: m.start, end: m.end, color: rule.color(cs)));
      }
    }

    // Sort and remove overlaps (first match wins).
    spans.sort((a, b) => a.start.compareTo(b.start));
    final merged = <({int start, int end, Color color})>[];
    for (final s in spans) {
      if (merged.isEmpty || s.start >= merged.last.end) {
        merged.add(s);
      }
    }

    final result = <TextSpan>[];
    int cursor = 0;
    for (final s in merged) {
      if (s.start > cursor) {
        result.add(TextSpan(
          text: line.substring(cursor, s.start),
          style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 12),
        ));
      }
      result.add(TextSpan(
        text: line.substring(s.start, s.end),
        style: TextStyle(color: s.color, fontFamily: 'monospace', fontSize: 12),
      ));
      cursor = s.end;
    }
    if (cursor < line.length) {
      result.add(TextSpan(
        text: line.substring(cursor),
        style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 12),
      ));
    }
    return result.isEmpty
        ? [TextSpan(text: line, style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 12))]
        : result;
  }
}

// ── Diff view widget ─────────────────────────────────────────────────────────

class GitDiffView extends StatefulWidget {
  final String filePath;
  final String originalContent;
  final String modifiedContent;
  final VoidCallback onClose;

  const GitDiffView({
    super.key,
    required this.filePath,
    required this.originalContent,
    required this.modifiedContent,
    required this.onClose,
  });

  @override
  State<GitDiffView> createState() => _GitDiffViewState();
}

class _GitDiffViewState extends State<GitDiffView> {
  late List<_DiffLine> _origLines;
  late List<_DiffLine> _modLines;
  final _origScroll = ScrollController();
  final _modScroll = ScrollController();
  bool _syncing = false;

  static const double _lineH = 20.0;

  @override
  void initState() {
    super.initState();
    _computeDiff();
    _origScroll.addListener(_onOrigScroll);
    _modScroll.addListener(_onModScroll);
  }

  @override
  void didUpdateWidget(GitDiffView old) {
    super.didUpdateWidget(old);
    if (old.originalContent != widget.originalContent ||
        old.modifiedContent != widget.modifiedContent) {
      _computeDiff();
    }
  }

  void _computeDiff() {
    final a = widget.originalContent.split('\n');
    final b = widget.modifiedContent.split('\n');
    final result = _Differ.compute(a, b);
    _origLines = result.orig;
    _modLines = result.mod;
  }

  void _onOrigScroll() {
    if (_syncing) return;
    _syncing = true;
    if (_modScroll.hasClients) {
      _modScroll.jumpTo(_origScroll.offset);
    }
    _syncing = false;
  }

  void _onModScroll() {
    if (_syncing) return;
    _syncing = true;
    if (_origScroll.hasClients) {
      _origScroll.jumpTo(_modScroll.offset);
    }
    _syncing = false;
  }

  @override
  void dispose() {
    _origScroll.dispose();
    _modScroll.dispose();
    super.dispose();
  }

  String get _ext {
    final dot = widget.filePath.lastIndexOf('.');
    return dot == -1 ? '' : widget.filePath.substring(dot + 1);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fileName = widget.filePath.split('/').last;

    return Column(
      children: [
        // ── Top half: HEAD (original) ─────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiffPaneHeader(
                label: '$fileName  (HEAD)',
                color: cs.surfaceContainerLow,
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Close diff',
                  onPressed: widget.onClose,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                ),
              ),
              Expanded(
                child: _DiffPane(
                  lines: _origLines,
                  scrollCtrl: _origScroll,
                  ext: _ext,
                  lineH: _lineH,
                  removedColor: const Color(0x40FF3B30),   // red tint
                  addedColor:   Colors.transparent,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 3, thickness: 3, color: cs.primary.withValues(alpha: 0.4)),
        // ── Bottom half: working copy (modified) ──────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DiffPaneHeader(
                label: '$fileName  (Working Tree)',
                color: cs.surfaceContainerLow,
              ),
              Expanded(
                child: _DiffPane(
                  lines: _modLines,
                  scrollCtrl: _modScroll,
                  ext: _ext,
                  lineH: _lineH,
                  removedColor: Colors.transparent,
                  addedColor:   const Color(0x3530D158),   // green tint
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DiffPaneHeader extends StatelessWidget {
  final String label;
  final Color color;
  final Widget? trailing;

  const _DiffPaneHeader({required this.label, required this.color, this.trailing});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 32,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(Icons.code, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _DiffPane extends StatelessWidget {
  final List<_DiffLine> lines;
  final ScrollController scrollCtrl;
  final String ext;
  final double lineH;
  final Color removedColor;
  final Color addedColor;

  const _DiffPane({
    required this.lines,
    required this.scrollCtrl,
    required this.ext,
    required this.lineH,
    required this.removedColor,
    required this.addedColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = cs.onSurface;
    final gutterColor = cs.onSurfaceVariant.withValues(alpha: 0.4);

    return Container(
      color: cs.surface,
      child: ListView.builder(
        controller: scrollCtrl,
        itemCount: lines.length,
        itemExtent: lineH,
        itemBuilder: (context, i) {
          final dl = lines[i];
          Color? bg;
          Color prefixColor = Colors.transparent;
          String prefix = ' ';

          switch (dl.kind) {
            case _DiffKind.removed:
              bg = removedColor;
              prefixColor = isDark ? Colors.red.shade300 : Colors.red.shade700;
              prefix = dl.text.isEmpty ? ' ' : '-';
              break;
            case _DiffKind.added:
              bg = addedColor;
              prefixColor = isDark ? Colors.green.shade300 : Colors.green.shade700;
              prefix = dl.text.isEmpty ? ' ' : '+';
              break;
            case _DiffKind.unchanged:
              bg = null;
              break;
          }

          final lineNoStr = dl.lineNo > 0 ? '${dl.lineNo}' : '';
          final spans = dl.text.isEmpty
              ? <TextSpan>[]
              : _Highlighter.highlight(dl.text, ext, cs, baseColor);

          return Container(
            height: lineH,
            color: bg,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Gutter — line number
                SizedBox(
                  width: 40,
                  child: Text(
                    lineNoStr,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11, color: gutterColor, fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // +/- prefix
                Text(
                  prefix,
                  style: TextStyle(
                    fontSize: 12, color: prefixColor,
                    fontFamily: 'monospace', fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                // Code content with syntax highlight
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const NeverScrollableScrollPhysics(),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: 'monospace', fontSize: 12,
                          height: 1.0, color: baseColor,
                        ),
                        children: spans,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Publish Branch dialog ─────────────────────────────────────────────────────

class _PublishBranchDialog extends StatefulWidget {
  final String branchName;
  final String defaultRepoName;
  final String githubUser;

  const _PublishBranchDialog({
    required this.branchName,
    required this.defaultRepoName,
    required this.githubUser,
  });

  @override
  State<_PublishBranchDialog> createState() => _PublishBranchDialogState();
}

class _PublishBranchDialogState extends State<_PublishBranchDialog> {
  late final TextEditingController _nameCtrl;
  bool _isPrivate = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.defaultRepoName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.cloud_upload_outlined, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          const Text('Publish Branch'),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Account row
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  widget.githubUser,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Repo name field
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Repository name',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.source_outlined),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'VISIBILITY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 6),
            _VisibilityOption(
              icon: Icons.lock_outline,
              label: 'Private',
              description: 'Only you and collaborators can see this.',
              selected: _isPrivate,
              onTap: () => setState(() => _isPrivate = true),
            ),
            const SizedBox(height: 6),
            _VisibilityOption(
              icon: Icons.public,
              label: 'Public',
              description: 'Anyone on the internet can see this.',
              selected: !_isPrivate,
              onTap: () => setState(() => _isPrivate = false),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: _nameCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    (repoName: _nameCtrl.text.trim(), isPrivate: _isPrivate),
                  ),
          icon: const Icon(Icons.cloud_upload_outlined, size: 16),
          label: const Text('Publish'),
        ),
      ],
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  const _VisibilityOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? cs.primary : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
          color: selected ? cs.primaryContainer.withValues(alpha: 0.3) : null,
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: selected ? cs.primary : cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.primary : cs.onSurface,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Radio<bool>(
              value: selected,
              groupValue: true,
              onChanged: (_) => onTap(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}
