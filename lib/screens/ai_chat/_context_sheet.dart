part of '../ai_chat_drawer.dart';

// ── Context file selector sheet ───────────────────────────────────────────────

class _ContextSheet extends StatefulWidget {
  final FileNode root;
  const _ContextSheet({required this.root});
  @override
  State<_ContextSheet> createState() => _ContextSheetState();
}

class _ContextSheetState extends State<_ContextSheet> {
  final Set<String> _expanded = {};
  final Set<String> _loading  = {};

  @override
  void initState() {
    super.initState();
    _expanded.add(widget.root.path);
  }

  Future<void> _toggleExpand(FileNode node) async {
    if (_expanded.contains(node.path)) {
      setState(() => _expanded.remove(node.path));
      return;
    }
    if (node.children.isEmpty) {
      setState(() => _loading.add(node.path));
      await node.loadChildren();
      if (!mounted) return;
      setState(() => _loading.remove(node.path));
    }
    setState(() => _expanded.add(node.path));
  }

  Future<List<String>> _collectFiles(FileNode node) async {
    if (!node.isDirectory) return [node.path];
    if (node.children.isEmpty) await node.loadChildren();
    final result = <String>[];
    for (final child in node.children) {
      result.addAll(await _collectFiles(child));
    }
    return result;
  }

  Future<void> _toggleFolder(FileNode node, ChatProvider chat) async {
    setState(() => _loading.add(node.path));
    final files = await _collectFiles(node);
    if (!mounted) return;
    setState(() => _loading.remove(node.path));
    final allSel = files.every((p) => chat.contextPaths.contains(p));
    for (final p in files) {
      if (allSel) {
        if (chat.contextPaths.contains(p)) chat.toggleContextPath(p);
      } else {
        if (!chat.contextPaths.contains(p)) chat.toggleContextPath(p);
      }
    }
  }

  List<String> _syncFiles(FileNode node) {
    if (!node.isDirectory) return [node.path];
    return node.children.expand(_syncFiles).toList();
  }

  List<(FileNode, int)> _flatten(FileNode node, int depth) {
    final result = <(FileNode, int)>[];
    if (depth == 0) {
      for (final child in node.children) result.addAll(_flatten(child, 1));
      return result;
    }
    result.add((node, depth));
    if (node.isDirectory && _expanded.contains(node.path)) {
      for (final child in node.children) result.addAll(_flatten(child, depth + 1));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final chat = context.watch<ChatProvider>();
    final items = _flatten(widget.root, 0);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (_, sc) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: cs.outlineVariant, borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
            child: Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Contexto extra',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface)),
                ),
                if (chat.contextPaths.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      chat.clearContext();
                      Navigator.pop(context);
                    },
                    child: Text('Limpar',
                        style: TextStyle(fontSize: 12, color: cs.error)),
                  ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('OK',
                      style: TextStyle(fontSize: 12, color: cs.primary)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: items.length,
              itemBuilder: (_, i) {
                final (node, depth) = items[i];
                final isDir = node.isDirectory;
                final loading = _loading.contains(node.path);
                final syncedFiles = _syncFiles(node);
                final allSel = syncedFiles.isNotEmpty &&
                    syncedFiles.every((p) => chat.contextPaths.contains(p));
                final anySel = syncedFiles.any((p) => chat.contextPaths.contains(p));
                return _ContextTreeTile(
                  node: node,
                  depth: depth,
                  isExpanded: isDir && _expanded.contains(node.path),
                  isLoading: loading,
                  isSelected: isDir ? allSel : chat.contextPaths.contains(node.path),
                  isIndeterminate: isDir && !allSel && anySel,
                  onTap: () {
                    if (isDir) {
                      _toggleExpand(node);
                    } else {
                      chat.toggleContextPath(node.path);
                    }
                  },
                  onCheckboxTap: () {
                    if (isDir) {
                      _toggleFolder(node, chat);
                    } else {
                      chat.toggleContextPath(node.path);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContextTreeTile extends StatelessWidget {
  final FileNode node;
  final int depth;
  final bool isExpanded;
  final bool isLoading;
  final bool isSelected;
  final bool isIndeterminate;
  final VoidCallback onTap;
  final VoidCallback onCheckboxTap;

  const _ContextTreeTile({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.isLoading,
    required this.isSelected,
    required this.isIndeterminate,
    required this.onTap,
    required this.onCheckboxTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final isDir = node.isDirectory;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(12.0 + (depth - 1) * 16.0, 0, 4, 0),
        child: SizedBox(
          height: 38,
          child: Row(
            children: [
              if (isDir)
                isLoading
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 1.5, color: cs.primary))
                    : Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant)
              else
                const SizedBox(width: 16),
              const SizedBox(width: 4),
              Icon(
                isDir
                    ? (isExpanded
                        ? Icons.folder_open_rounded
                        : Icons.folder_rounded)
                    : Icons.insert_drive_file_outlined,
                size: 15,
                color: isDir ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: cs.onSurface)),
              ),
              SizedBox(
                width: 36,
                child: Checkbox(
                  value: isIndeterminate ? null : isSelected,
                  tristate: true,
                  onChanged: (_) => onCheckboxTap(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  activeColor: cs.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
