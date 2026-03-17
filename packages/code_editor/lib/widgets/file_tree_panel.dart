import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';

class FileTreePanel extends StatelessWidget {
  const FileTreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        return Container(
          color: AppTheme.darkSidebar,
          child: editor.rootNode == null
              ? const Center(
                  child: Text('No project open',
                      style: TextStyle(
                          color: AppTheme.darkTextMuted, fontSize: 14)),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: _FileTreeNode(node: editor.rootNode!, depth: 0),
                ),
        );
      },
    );
  }
}

class _FileTreeNode extends StatelessWidget {
  final FileNode node;
  final int depth;

  const _FileTreeNode({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) =>
      node.isDirectory
          ? _DirectoryNode(node: node, depth: depth)
          : _FileNode(node: node, depth: depth);
}

class _DirectoryNode extends StatelessWidget {
  final FileNode node;
  final int depth;

  const _DirectoryNode({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
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
            color: AppTheme.darkTextMuted,
          ),
          icon: Icons.folder_rounded,
          iconColor: const Color(0xFF90B4E8),
          label: node.name,
          onTap: () => context.read<EditorProvider>().expandNode(node),
        ),
        if (node.isExpanded)
          ...node.children.map((child) =>
              _FileTreeNode(node: child, depth: depth + 1)),
      ],
    );
  }
}

class _FileNode extends StatelessWidget {
  final FileNode node;
  final int depth;

  const _FileNode({required this.node, required this.depth});

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
        Navigator.of(context).pop(); // close file tree
      },
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
      default:         return AppTheme.darkTextDim;
    }
  }
}

class _TreeItem extends StatefulWidget {
  final FileNode node;
  final int depth;
  final Widget? leading;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TreeItem({
    required this.node,
    required this.depth,
    this.leading,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.isActive = false,
    required this.onTap,
  });

  @override
  State<_TreeItem> createState() => _TreeItemState();
}

class _TreeItemState extends State<_TreeItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: 36,
          padding: EdgeInsets.only(
              left: 8.0 + widget.depth * 16.0, right: 8),
          color: widget.isActive
              ? AppTheme.darkTreeSelected
              : _hovered
                  ? AppTheme.darkTreeHover
                  : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 22,
                child: widget.leading,
              ),
              const SizedBox(width: 6),
              Icon(widget.icon, size: 18, color: widget.iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? AppTheme.darkText
                        : AppTheme.darkText,
                    fontSize: 15,
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
