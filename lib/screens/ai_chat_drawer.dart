import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code_editor/code_editor.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/ai_agent.dart';
import '../providers/ai_provider.dart';
import '../providers/chat_provider.dart';

part 'ai_chat/_header.dart';
part 'ai_chat/_history.dart';
part 'ai_chat/_chat_view.dart';
part 'ai_chat/_agent_bar.dart';
part 'ai_chat/_user_message.dart';
part 'ai_chat/_ai_message.dart';
part 'ai_chat/_message_content.dart';
part 'ai_chat/_file_op_card.dart';
part 'ai_chat/_rich_text.dart';
part 'ai_chat/_input_area.dart';
part 'ai_chat/_context_sheet.dart';

// Lookup a default agent by id (used for orchestrator phase agents)
AiAgent _agentById(String id) =>
    kDefaultAgents.firstWhere((a) => a.id == id,
        orElse: () => kDefaultAgents.first);

// ─────────────────────────────────────────────────────────────────────────────
// System-prompt template injected automatically for every message
// ─────────────────────────────────────────────────────────────────────────────

const _kAgentInstructions = '''
You are an AI coding agent embedded in FL IDE with FULL read/write access to the project.

## File Operations
To propose file changes, use these exact XML tags in your response:

**Write / create a file** (always write the COMPLETE file content):
<fl_write path="lib/example.dart" lang="dart">
// complete file content here
</fl_write>

**Delete a file or folder:**
<fl_delete path="lib/old_file.dart"/>

**Rename or move:**
<fl_rename from="lib/old.dart" to="new/path.dart"/>

**Create a directory:**
<fl_mkdir path="lib/new_feature"/>

**Run a terminal command** (executed in the project root, inside Termux Linux environment):
<fl_terminal cmd="flutter pub get"/>
<fl_terminal cmd="dart format lib/"/>
<fl_terminal cmd="flutter build apk --release"/>
<fl_terminal cmd="npm install"/>

Rules:
- Use paths relative to the project root shown below
- Write the COMPLETE file content in <fl_write> — never partial snippets
- Explain what you are doing BEFORE each operation tag
- You may propose multiple operations in one response
- The user will review each change and Accept or Reject it
- Terminal commands run with full Termux PATH (flutter, dart, npm, git, etc. are available)
- Use <fl_terminal> for package installs, builds, formatting, code generation, git operations
''';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

class AiChatDrawer extends StatefulWidget {
  final VoidCallback onClose;
  final Project project;

  const AiChatDrawer({
    super.key,
    required this.onClose,
    required this.project,
  });

  @override
  State<AiChatDrawer> createState() => _AiChatDrawerState();
}

class _AiChatDrawerState extends State<AiChatDrawer> {
  final _inputCtrl  = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();
  bool _showHistory = false;
  bool _buildingCtx = false;

  @override
  void initState() {
    super.initState();
    // Load persisted history for this project
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await context.read<ChatProvider>().loadProject(widget.project.path);
    });
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Project context ────────────────────────────────────────────────────────

  static const _kSkipDirs = {
    '.git', '.dart_tool', 'build', '.gradle', 'node_modules', '__pycache__',
    '.idea', '.vscode', '.flutter-plugins', '.flutter-plugins-dependencies',
  };
  static const _kSkipExts = {
    'png', 'jpg', 'jpeg', 'gif', 'svg', 'ico', 'ttf', 'otf',
    'woff', 'woff2', 'eot', 'pdf', 'zip', 'jar', 'class', 'so', 'apk',
    'aab', 'dex', 'keystore', 'jks', 'lock',
  };

  /// Build the complete system prompt by scanning the project directory directly
  /// from the filesystem (not from EditorProvider, which only loads 1 level).
  Future<AiAgent> _buildAgentWithContext(AiAgent base) async {
    final projectPath = widget.project.path;
    final projectDir  = Directory(projectPath);

    const maxTotal = 80 * 1024; // 80 KB total file content
    const maxFile  = 12 * 1024; // 12 KB per file

    // Collect all text files recursively
    final allFiles = <String>[];
    try {
      await for (final entity
          in projectDir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        // Build relative path segments to check for hidden dirs
        final rel = entity.path.substring(projectPath.length);
        final segments = rel.split(RegExp(r'[/\\]'))..removeWhere((s) => s.isEmpty);
        if (segments.any((s) => _kSkipDirs.contains(s))) continue;
        final ext = entity.path.split('.').last.toLowerCase();
        if (_kSkipExts.contains(ext)) continue;
        allFiles.add(entity.path);
      }
    } catch (_) {}

    allFiles.sort();

    final buf = StringBuffer(_kAgentInstructions);
    buf.write('\n\n## Project: ${widget.project.name}\n');
    buf.write('Root: $projectPath\n\n');

    // File tree (relative paths)
    buf.write('## File Tree\n```\n');
    for (final path in allFiles) {
      final rel = path.substring(projectPath.length).replaceAll('\\', '/');
      buf.write('$rel\n');
    }
    buf.write('```\n\n');

    // File contents
    buf.write('## File Contents\n');
    int totalBytes = 0;
    for (final path in allFiles) {
      if (totalBytes >= maxTotal) {
        buf.write('\n… (limite de contexto atingido, ${allFiles.length} arquivos no total)\n');
        break;
      }
      try {
        final bytes = await File(path).readAsBytes();
        // Skip binary files: null bytes anywhere in first 512 bytes = binary
        final sample = bytes.length > 512 ? bytes.sublist(0, 512) : bytes;
        if (sample.contains(0)) continue;
        final raw = utf8.decode(bytes, allowMalformed: false);
        final content = raw.length > maxFile
            ? '${raw.substring(0, maxFile)}\n… (truncado)'
            : raw;
        final rel = path.substring(projectPath.length).replaceAll('\\', '/');
        final ext = path.split('.').last.toLowerCase();
        buf.write('\n### $rel\n```$ext\n$content\n```\n');
        totalBytes += content.length;
      } catch (_) {}
    }

    buf.write('\n\n---\n\n');
    buf.write(base.instructions);

    return base.copyWith(instructions: buf.toString());
  }

  // ── Send ──────────────────────────────────────────────────────────────────

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();

    final chat = context.read<ChatProvider>();
    final ai   = context.read<AiProvider>();

    // Save snapshot metadata for this user-message block
    final snapshotId = DateTime.now().millisecondsSinceEpoch.toString();
    final msgIndex   = chat.userMessageCount + 1;
    final preview    = text.length > 46 ? '${text.substring(0, 46)}…' : text;
    _pendingSnapshotId    = snapshotId;
    _pendingSnapshotIndex = msgIndex;
    _pendingSnapshotPreview = preview;
    _pendingBackups.clear();

    final agent = chat.selectedAgent;

    if (agent.isOrchestrator) {
      // Build context-augmented versions of both sub-agents
      if (mounted) setState(() => _buildingCtx = true);
      final planAgent = await _buildAgentWithContext(
          _agentById(agent.planAgentId));
      final implAgent = await _buildAgentWithContext(
          _agentById(agent.implAgentId));
      if (mounted) setState(() => _buildingCtx = false);

      chat.sendOrchestratedMessage(text, ai, planAgent, implAgent);
    } else {
      if (mounted) setState(() => _buildingCtx = true);
      final augmented = await _buildAgentWithContext(agent);
      if (mounted) setState(() => _buildingCtx = false);

      chat.sendMessage(text, ai, agentOverride: augmented);
    }

    _scrollToBottom();
  }

  // ── Pending snapshot (built lazily as ops are accepted) ────────────────────

  String? _pendingSnapshotId;
  int     _pendingSnapshotIndex = 0;
  String  _pendingSnapshotPreview = '';
  final Map<String, String?> _pendingBackups = {};

  Future<void> _executeOperation(FileOperation op) async {
    final root = widget.project.path;
    final fullPath = _resolvePath(root, op.path);
    final chat     = context.read<ChatProvider>();

    // Backup before first modification
    if (_pendingSnapshotId != null &&
        !_pendingBackups.containsKey(fullPath)) {
      final f = File(fullPath);
      if (await f.exists()) {
        try {
          _pendingBackups[fullPath] = await f.readAsString();
        } catch (_) {
          _pendingBackups[fullPath] = null;
        }
      } else {
        _pendingBackups[fullPath] = null; // new file — nothing to back up
      }
    }

    switch (op.type) {
      case FileOpType.write:
        final f = File(fullPath);
        await f.parent.create(recursive: true);
        await f.writeAsString(op.content ?? '');
        // Close the stale editor tab so next open loads fresh content from disk.
        if (mounted) context.read<EditorProvider>().reloadFile(fullPath);
        break;

      case FileOpType.delete:
        final type = FileSystemEntity.typeSync(fullPath);
        if (type == FileSystemEntityType.directory) {
          await Directory(fullPath).delete(recursive: true);
        } else if (type == FileSystemEntityType.file) {
          await File(fullPath).delete();
        }
        break;

      case FileOpType.rename:
        if (op.newPath == null) break;
        final newFull = _resolvePath(root, op.newPath!);
        final type = FileSystemEntity.typeSync(fullPath);
        if (type == FileSystemEntityType.directory) {
          await Directory(fullPath).rename(newFull);
        } else {
          final dest = File(newFull);
          await dest.parent.create(recursive: true);
          await File(fullPath).rename(newFull);
        }
        break;

      case FileOpType.mkdir:
        await Directory(fullPath).create(recursive: true);
        break;

      case FileOpType.terminal:
        if (op.command == null || op.command!.isEmpty) break;
        try {
          final result = await Process.run(
            '/data/data/com.termux/files/usr/bin/bash',
            ['-c', op.command!],
            workingDirectory: root,
            environment: {
              ...RuntimeEnvir.baseEnv,
              'HOME': '/data/data/com.termux/files/home',
            },
            runInShell: false,
          );
          final stdout = result.stdout as String? ?? '';
          final stderr = result.stderr as String? ?? '';
          final output = [
            if (stdout.trim().isNotEmpty) stdout.trim(),
            if (stderr.trim().isNotEmpty) '--- stderr ---\n${stderr.trim()}',
          ].join('\n');
          if (mounted) {
            chat.setOperationOutput(
              chat.activeConversation!.messages
                  .firstWhere((m) => m.operations.any((o) => o.id == op.id))
                  .id,
              op.id,
              output.isEmpty ? '(sem saída)' : output,
            );
          }
        } catch (e) {
          if (mounted) {
            chat.setOperationOutput(
              chat.activeConversation!.messages
                  .firstWhere((m) => m.operations.any((o) => o.id == op.id))
                  .id,
              op.id,
              'Erro ao executar: $e',
            );
          }
        }
        return; // snapshot not needed for terminal commands
    }

    // Commit snapshot after first accepted op
    if (_pendingSnapshotId != null && _pendingBackups.isNotEmpty) {
      final snap = ProjectSnapshot(
        id: _pendingSnapshotId!,
        userMessageIndex: _pendingSnapshotIndex,
        messagePreview: _pendingSnapshotPreview,
        timestamp: DateTime.now(),
        fileBackups: Map.from(_pendingBackups),
      );
      chat.addSnapshot(snap);
      _pendingSnapshotId = null; // commit once per user-message block
    }

    // Refresh the file tree in the editor
    if (mounted) context.read<EditorProvider>().refreshTree();
  }

  String _resolvePath(String root, String path) {
    if (path.startsWith('/') || path.contains(':')) return path;
    return '$root/$path';
  }

  // ── Resend edited message ─────────────────────────────────────────────────

  Future<void> _resend(
      ChatMessage msg, String newText, bool restoreFirst) async {
    final chat = context.read<ChatProvider>();
    final ai   = context.read<AiProvider>();

    if (restoreFirst) {
      // Find the snapshot that was created when this message was sent.
      // We stored userMessageCount on the snapshot; match by looking for
      // a snapshot whose preview matches the original text.
      final snap = chat.snapshots.firstWhere(
        (s) => s.messagePreview == (msg.text.length > 46
            ? '${msg.text.substring(0, 46)}…'
            : msg.text),
        orElse: () => chat.snapshots.isNotEmpty
            ? chat.snapshots.last
            : ProjectSnapshot(
                id: '',
                userMessageIndex: 0,
                messagePreview: '',
                timestamp: DateTime.now(),
                fileBackups: const {},
              ),
      );
      if (snap.fileBackups.isNotEmpty) await _restoreSnapshot(snap);
    }

    if (!mounted) return;

    if (mounted) setState(() => _buildingCtx = true);
    final augmented = await _buildAgentWithContext(chat.selectedAgent);
    if (mounted) setState(() => _buildingCtx = false);

    if (!mounted) return;
    chat.editAndResend(msg.id, newText, ai, agentOverride: augmented);
    _scrollToBottom();
  }

  // ── Restore snapshot ───────────────────────────────────────────────────────

  Future<void> _restoreSnapshot(ProjectSnapshot snap) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar versão?'),
        content: Text(
          'Restaurar os arquivos para o estado antes da mensagem ${snap.userMessageIndex}:\n"${snap.messagePreview}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    for (final entry in snap.fileBackups.entries) {
      try {
        if (entry.value == null) {
          // File didn't exist before — delete it
          final f = File(entry.key);
          if (f.existsSync()) await f.delete();
        } else {
          final f = File(entry.key);
          await f.parent.create(recursive: true);
          await f.writeAsString(entry.value!);
        }
      } catch (_) {}
    }

    if (mounted) {
      context.read<EditorProvider>().refreshTree();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Versão restaurada com sucesso')),
      );
    }
  }

  // ── Context sheet ──────────────────────────────────────────────────────────

  void _showContextSheet() {
    final root = context.read<EditorProvider>().rootNode;
    if (root == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ChangeNotifierProvider.value(
        value: context.read<ChatProvider>(),
        child: _ContextSheet(root: root),
      ),
    );
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: SafeArea(
        child: Column(
          children: [
            _Header(
              onClose: widget.onClose,
              showHistory: _showHistory,
              onToggleHistory: () => setState(() => _showHistory = !_showHistory),
            ),
            Divider(height: 1, thickness: 1, color: cs.outlineVariant),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: _showHistory
                    ? _HistoryView(
                        key: const ValueKey('history'),
                        onSelect: () => setState(() => _showHistory = false),
                        onRestore: _restoreSnapshot,
                      )
                    : _ChatView(
                        key: const ValueKey('chat'),
                        scrollCtrl: _scrollCtrl,
                        inputCtrl: _inputCtrl,
                        focusNode: _focusNode,
                        onSend: _send,
                        onScrollToBottom: _scrollToBottom,
                        onAttach: _showContextSheet,
                        onExecuteOp: _executeOperation,
                        onResend: _resend,
                        isBuildingCtx: _buildingCtx,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

