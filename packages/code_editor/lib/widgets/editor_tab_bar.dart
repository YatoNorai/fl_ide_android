import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/editor_provider.dart';

class EditorTabBar extends StatefulWidget {
  const EditorTabBar({super.key});

  @override
  State<EditorTabBar> createState() => _EditorTabBarState();
}

class _EditorTabBarState extends State<EditorTabBar>
    with TickerProviderStateMixin {
  late TabController _ctrl;
  bool _closeHandled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TabController(length: 0, vsync: this);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _syncController(int len, int active) {
    if (_ctrl.length != len) {
      final old = _ctrl;
      _ctrl = TabController(length: len, vsync: this, initialIndex: active);
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } else if (len > 0 && _ctrl.index != active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl.length > active) _ctrl.index = active;
      });
    }
  }

  void _showMenu(BuildContext ctx, EditorProvider editor, int globalIndex) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = box.size;
    showMenu<String>(
      context: ctx,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(
          origin.dx + 8, origin.dy + size.height, origin.dx + size.width, 0),
      items: [
        PopupMenuItem(
          value: 'close',
          height: 40,
          child: _MenuItem(icon: Icons.close, label: 'Close'),
        ),
        PopupMenuItem(
          value: 'others',
          height: 40,
          child:
              _MenuItem(icon: Icons.tab_unselected, label: 'Close others'),
        ),
        PopupMenuItem(
          value: 'all',
          height: 40,
          child: _MenuItem(icon: Icons.clear_all, label: 'Close all'),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'panel',
          height: 40,
          child: _MenuItem(
              icon: Icons.vertical_align_bottom_rounded,
              label: 'Move to panel'),
        ),
      ],
    ).then((val) {
      if (!mounted) return;
      if (val == 'close') editor.closeFile(globalIndex);
      if (val == 'others') editor.closeOthers(globalIndex);
      if (val == 'all') editor.closeAll();
      if (val == 'panel') editor.moveToPanel(globalIndex, bottom: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EditorProvider>(
      builder: (ctx, editor, _) {
        final topFiles = editor.topFiles;
        if (topFiles.isEmpty) return const SizedBox.shrink();

        final len = topFiles.length;
        // Active tab index within topFiles list
        final activeGlobal = editor.activeIndex;
        final activeTop = topFiles.indexWhere(
            (f) => editor.openFiles.indexOf(f) == activeGlobal);
        final active = activeTop < 0 ? 0 : activeTop;

        _syncController(len, active);

        final cs = Theme.of(context).colorScheme;

        // Wrap the entire bar in a DragTarget so bottom-panel tabs
        // can be dragged back to the top bar.
        return DragTarget<OpenFile>(
          onAcceptWithDetails: (details) {
            final globalIndex =
                editor.openFiles.indexOf(details.data);
            if (globalIndex != -1) {
              editor.moveToPanel(globalIndex, bottom: false);
            }
          },
          builder: (ctx2, candidates, _) {
            final isDragOver = candidates.isNotEmpty;
            return ColoredBox(
              color: isDragOver
                  ? cs.primaryContainer.withValues(alpha: 0.3)
                  : cs.surfaceContainerHigh,
              child: TabBar(
                controller: _ctrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                padding: EdgeInsets.zero,
                labelPadding: EdgeInsets.zero,
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w400),
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                onTap: (i) {
                  if (_closeHandled) return;
                  final globalIndex =
                      editor.openFiles.indexOf(topFiles[i]);
                  if (i == active) {
                    _showMenu(ctx, editor, globalIndex);
                  } else {
                    editor.switchTo(globalIndex);
                  }
                },
                tabs: List.generate(len, (i) {
                  final f = topFiles[i];
                  final globalIndex = editor.openFiles.indexOf(f);
                  return Tab(
                    height: 38,
                    child: LongPressDraggable<OpenFile>(
                      data: f,
                      feedback: Material(
                        elevation: 4,
                        borderRadius: BorderRadius.circular(8),
                        color: cs.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          child: Text(
                            f.name,
                            style: TextStyle(
                                color: cs.onPrimaryContainer,
                                fontSize: 12,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      childWhenDragging: Opacity(
                        opacity: 0.4,
                        child: _TabContent(
                            file: f,
                            cs: cs,
                            onClose: () {},
                            closeHandled: false),
                      ),
                      child: _TabContent(
                        file: f,
                        cs: cs,
                        onClose: () {
                          _closeHandled = true;
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _closeHandled = false);
                          editor.closeFile(globalIndex);
                        },
                        closeHandled: _closeHandled,
                      ),
                    ),
                  );
                }),
              ),
            );
          },
        );
      },
    );
  }
}

class _TabContent extends StatelessWidget {
  final OpenFile file;
  final ColorScheme cs;
  final VoidCallback onClose;
  final bool closeHandled;

  const _TabContent({
    required this.file,
    required this.cs,
    required this.onClose,
    required this.closeHandled,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (file.isDirty)
            Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 6),
              decoration:
                  BoxDecoration(color: cs.error, shape: BoxShape.circle),
            ),
          Text(file.name),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Icon(Icons.close_rounded,
                size: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 16, color: cs.onSurface),
      const SizedBox(width: 10),
      Text(label, style: TextStyle(color: cs.onSurface, fontSize: 13)),
    ]);
  }
}
