import 'dart:io';

import 'package:core/core.dart' show FileNode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';

class FileTreePanel extends StatelessWidget {
  final VoidCallback? onFileSelected;
  const FileTreePanel({super.key, this.onFileSelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        return ColoredBox(
          color: cs.surfaceContainerLow,
          child: editor.rootNode == null
              ? Center(
                  child: Text('No project open',
                      style: TextStyle(
                          color: cs.onSurfaceVariant, fontSize: 14)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _FileTreeNode(
                    node: editor.rootNode!,
                    depth: 0,
                    onFileSelected: onFileSelected,
                  ),
                ),
        );
      },
    );
  }
}

// ── Tree routing ──────────────────────────────────────────────────────────────

class _FileTreeNode extends StatelessWidget {
  final FileNode node;
  final int depth;
  final VoidCallback? onFileSelected;
  const _FileTreeNode(
      {required this.node, required this.depth, this.onFileSelected});

  @override
  Widget build(BuildContext context) => node.isDirectory
      ? _DirectoryNode(
          node: node, depth: depth, onFileSelected: onFileSelected)
      : _FileLeaf(
          node: node, depth: depth, onFileSelected: onFileSelected);
}

// ── Directory node ────────────────────────────────────────────────────────────

class _DirectoryNode extends StatelessWidget {
  final FileNode node;
  final int depth;
  final VoidCallback? onFileSelected;
  const _DirectoryNode(
      {required this.node, required this.depth, this.onFileSelected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TreeItem(
          node: node,
          depth: depth,
          leading: Icon(
            node.isExpanded
                ? Icons.keyboard_arrow_down
                : Icons.chevron_right,
            size: 20,
            color: cs.onSurfaceVariant,
          ),
          icon: Icons.folder_rounded,
          iconColor: const Color(0xFF90B4E8),
          label: node.name,
          onTap: () => context.read<EditorProvider>().expandNode(node),
          onLongPress: () => _showDirSheet(context, node),
        ),
        if (node.isExpanded)
          ...node.children.map((child) => _FileTreeNode(
              node: child,
              depth: depth + 1,
              onFileSelected: onFileSelected)),
      ],
    );
  }

  void _showDirSheet(BuildContext context, FileNode dir) {
    final editor = context.read<EditorProvider>();
    // Capture parent context before sheet opens so action dialogs can use it.
    final parentCtx = context;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _DirActionsSheet(
        dir: dir,
        parentContext: parentCtx,
        onRefresh: editor.refreshTree,
        onCloseUnder: (path) => editor.closeFilesUnderPath(path),
        onOpenFile: editor.openFile,
      ),
    );
  }
}

// ── File leaf ─────────────────────────────────────────────────────────────────

class _FileLeaf extends StatelessWidget {
  final FileNode node;
  final int depth;
  final VoidCallback? onFileSelected;
  const _FileLeaf(
      {required this.node, required this.depth, this.onFileSelected});

  @override
  Widget build(BuildContext context) {
    final editor = context.watch<EditorProvider>();
    final isActive = editor.activeFile?.path == node.path;
    return _TreeItem(
      node: node,
      depth: depth,
      icon: _fileIcon(node.extension),
      iconColor: _fileIconColor(node.extension),
      label: node.name,
      isActive: isActive,
      onTap: () {
        context.read<EditorProvider>().openFile(node.path);
        onFileSelected?.call();
      },
      onLongPress: () => _showFileSheet(context, node),
    );
  }

  void _showFileSheet(BuildContext context, FileNode file) {
    final editor = context.read<EditorProvider>();
    final parentCtx = context;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _FileActionsSheet(
        file: file,
        parentContext: parentCtx,
        onRefresh: editor.refreshTree,
        onCloseFile: () {
          final idx =
              editor.openFiles.indexWhere((f) => f.path == file.path);
          if (idx != -1) editor.closeFile(idx);
        },
      ),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':     return Icons.flutter_dash;
      case 'yaml':
      case 'yml':      return Icons.settings_outlined;
      case 'json':     return Icons.data_object_outlined;
      case 'md':       return Icons.article_outlined;
      case 'kt':
      case 'kts':      return Icons.code;
      case 'java':     return Icons.coffee;
      case 'js':
      case 'mjs':      return Icons.javascript;
      case 'ts':
      case 'tsx':
      case 'jsx':      return Icons.code;
      case 'py':       return Icons.terminal;
      case 'xml':      return Icons.code;
      case 'html':     return Icons.html;
      case 'css':      return Icons.style_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'svg':      return Icons.image_outlined;
      case 'sh':
      case 'bash':     return Icons.terminal;
      case 'gradle':   return Icons.build_outlined;
      case 'bat':      return Icons.terminal;
      default:         return Icons.insert_drive_file_outlined;
    }
  }

  Color _fileIconColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':     return const Color(0xFF54C5F8);
      case 'yaml':
      case 'yml':      return const Color(0xFFE8C96B);
      case 'json':     return const Color(0xFFABB2BF);
      case 'kt':
      case 'kts':      return const Color(0xFFA97BFF);
      case 'java':     return const Color(0xFFF0AB00);
      case 'js':
      case 'mjs':      return const Color(0xFFF7DF1E);
      case 'ts':
      case 'tsx':      return const Color(0xFF3178C6);
      case 'jsx':      return const Color(0xFF61DAFB);
      case 'py':       return const Color(0xFF3572A5);
      case 'html':     return const Color(0xFFE34C26);
      case 'xml':      return const Color(0xFFE4A600);
      case 'css':      return const Color(0xFF264DE4);
      case 'gradle':   return const Color(0xFF00C4BB);
      case 'sh':
      case 'bash':
      case 'bat':      return const Color(0xFF89DDFF);
      case 'md':       return const Color(0xFF9CA3AF);
      default:         return const Color(0xFF9CA3AF);
    }
  }
}

// ── Tree item (row widget) ────────────────────────────────────────────────────

class _TreeItem extends StatefulWidget {
  final FileNode node;
  final int depth;
  final Widget? leading;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _TreeItem({
    required this.node,
    required this.depth,
    this.leading,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.isActive = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_TreeItem> createState() => _TreeItemState();
}

class _TreeItemState extends State<_TreeItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          height: 36,
          padding:
              EdgeInsets.only(left: 8.0 + widget.depth * 16.0, right: 8),
          color: widget.isActive
              ? cs.primaryContainer
              : _hovered
                  ? cs.surfaceContainerHigh
                  : Colors.transparent,
          child: Row(
            children: [
              SizedBox(width: 22, child: widget.leading),
              const SizedBox(width: 6),
              Icon(widget.icon, size: 18, color: widget.iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? cs.onPrimaryContainer
                        : cs.onSurface,
                    fontSize: 14,
                    fontWeight: widget.isActive
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── File context sheet ────────────────────────────────────────────────────────

class _FileActionsSheet extends StatelessWidget {
  final FileNode file;
  final BuildContext parentContext;
  final VoidCallback onRefresh;
  final VoidCallback onCloseFile;

  const _FileActionsSheet({
    required this.file,
    required this.parentContext,
    required this.onRefresh,
    required this.onCloseFile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(file.name,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            _SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: cs.error,
              onTap: () => _confirmDelete(context),
            ),
            _SheetAction(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
              onTap: () => _showRename(context),
            ),
            _SheetAction(
              icon: Icons.copy_outlined,
              label: 'Copy path',
              onTap: () {
                Clipboard.setData(ClipboardData(text: file.path));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path copied')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete file?'),
        content: Text('Delete "${file.name}"? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                onCloseFile();
                await File(file.path).delete();
                onRefresh();
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showRename(BuildContext context) {
    Navigator.pop(context);
    final ctrl = TextEditingController(text: file.name);
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename file'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              final parent = file.path.substring(0, file.path.lastIndexOf('/'));
              try {
                await File(file.path).rename('$parent/$newName');
                onRefresh();
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

// ── Directory context sheet ───────────────────────────────────────────────────

class _DirActionsSheet extends StatelessWidget {
  final FileNode dir;
  final BuildContext parentContext;
  final VoidCallback onRefresh;
  final void Function(String path) onCloseUnder;
  final Future<void> Function(String path) onOpenFile;

  const _DirActionsSheet({
    required this.dir,
    required this.parentContext,
    required this.onRefresh,
    required this.onCloseUnder,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.folder_rounded,
                    size: 16, color: const Color(0xFF90B4E8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(dir.name,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            _SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: cs.error,
              onTap: () => _confirmDelete(context),
            ),
            _SheetAction(
              icon: Icons.note_add_outlined,
              label: 'New file',
              onTap: () => _showNewItem(context, isFile: true),
            ),
            _SheetAction(
              icon: Icons.create_new_folder_outlined,
              label: 'New folder',
              onTap: () => _showNewItem(context, isFile: false),
            ),
            _SheetAction(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
              onTap: () => _showRename(context),
            ),
            _SheetAction(
              icon: Icons.copy_outlined,
              label: 'Copy path',
              onTap: () {
                Clipboard.setData(ClipboardData(text: dir.path));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Path copied')));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    Navigator.pop(context);
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete folder?'),
        content: Text(
            'Delete "${dir.name}" and all its contents? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                onCloseUnder(dir.path);
                await Directory(dir.path).delete(recursive: true);
                onRefresh();
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showNewItem(BuildContext context, {required bool isFile}) {
    Navigator.pop(context);
    final ctrl = TextEditingController();
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isFile ? 'New file' : 'New folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFile ? 'filename.dart' : 'folder_name',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final name = ctrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final newPath = '${dir.path}/$name';
              try {
                if (isFile) {
                  await File(newPath).create(recursive: true);
                  onRefresh();
                  await onOpenFile(newPath);
                } else {
                  await Directory(newPath).create(recursive: true);
                  onRefresh();
                }
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showRename(BuildContext context) {
    Navigator.pop(context);
    final ctrl = TextEditingController(text: dir.name);
    showDialog(
      context: parentContext,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Rename folder'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
              Navigator.pop(ctx);
              final parent = dir.path.substring(0, dir.path.lastIndexOf('/'));
              try {
                await Directory(dir.path).rename('$parent/$newName');
                onRefresh();
              } catch (e) {
                if (parentContext.mounted) {
                  ScaffoldMessenger.of(parentContext)
                      .showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }
}

// ── Shared action row widget ──────────────────────────────────────────────────

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 22, color: c),
      title: Text(label, style: TextStyle(color: c, fontSize: 14)),
      onTap: onTap,
    );
  }
}
