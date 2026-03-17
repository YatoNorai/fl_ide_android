import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';

class EditorTabBar extends StatelessWidget {
  const EditorTabBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (context, editor, _) {
        if (editor.openFiles.isEmpty) return const SizedBox.shrink();

        return Container(
          height: 36,
          color: AppTheme.darkSideRail,
          child: Row(
            children: [
              Expanded(
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: editor.openFiles.length,
                  itemBuilder: (context, i) {
                    final f = editor.openFiles[i];
                    final isActive = i == editor.activeIndex;
                    return _EditorTab(
                      file: f,
                      isActive: isActive,
                      onTap: () => editor.switchTo(i),
                      onClose: () => editor.closeFile(i),
                    );
                  },
                ),
              ),
              if (editor.activeFile?.isDirty == true)
                IconButton(
                  icon: const Icon(Icons.save_rounded, size: 15),
                  color: AppTheme.darkWarning,
                  onPressed: editor.saveActiveFile,
                  tooltip: 'Save',
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 36),
                  padding: const EdgeInsets.all(8),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EditorTab extends StatefulWidget {
  final OpenFile file;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _EditorTab({
    required this.file,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  State<_EditorTab> createState() => _EditorTabState();
}

class _EditorTabState extends State<_EditorTab> {
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppTheme.darkBg
                : _hovered
                    ? AppTheme.darkSurface
                    : Colors.transparent,
            border: widget.isActive
                ? const Border(
                    top: BorderSide(color: AppTheme.darkAccent, width: 2))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.file.isDirty)
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: AppTheme.darkWarning,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                widget.file.name,
                style: TextStyle(
                  color: widget.isActive
                      ? AppTheme.darkText
                      : AppTheme.darkTextMuted,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: widget.onClose,
                child: Opacity(
                  opacity: _hovered || widget.isActive ? 1.0 : 0.0,
                  child: const Icon(Icons.close_rounded,
                      size: 12, color: AppTheme.darkTextMuted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
