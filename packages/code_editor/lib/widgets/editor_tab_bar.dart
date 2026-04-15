import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

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
  Offset? _lastTapPosition;

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
      _ctrl = TabController(length: len, vsync: this, initialIndex: active.clamp(0, len - 1));
      WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    } else if (len > 0 && _ctrl.index != active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _ctrl.length > active) _ctrl.index = active;
      });
    }
  }

  void _showFileMenu(BuildContext ctx, EditorProvider editor, int globalIndex) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final tabBarOrigin = box.localToGlobal(Offset.zero);
    final tabBarBottom = tabBarOrigin.dy + box.size.height;
    // Use the tap X position so the menu appears below the tapped tab.
    // Fall back to tab bar left if no tap was recorded.
    final tapX = _lastTapPosition?.dx ?? (tabBarOrigin.dx + 8);
    showMenu<String>(
      context: ctx,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(tapX - 8, tabBarBottom, tapX + 200, 0),
      items: [
        PopupMenuItem(value: 'close', height: 40, child: _MenuItem(icon: Icons.close, label: 'Close')),
        PopupMenuItem(value: 'others', height: 40, child: _MenuItem(icon: Icons.tab_unselected, label: 'Close others')),
        PopupMenuItem(value: 'all', height: 40, child: _MenuItem(icon: Icons.clear_all, label: 'Close all')),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'panel', height: 40, child: _MenuItem(icon: Icons.vertical_align_bottom_rounded, label: 'Move to panel')),
      ],
    ).then((val) {
      if (!mounted) return;
      if (val == 'close') editor.closeFile(globalIndex);
      if (val == 'others') editor.closeOthers(globalIndex);
      if (val == 'all') editor.closeAll();
      if (val == 'panel') editor.moveToPanel(globalIndex, bottom: true);
    });
  }

  void _showTerminalMenu(BuildContext ctx, TerminalProvider term, String sessionId) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final tabBarOrigin = box.localToGlobal(Offset.zero);
    final tabBarBottom = tabBarOrigin.dy + box.size.height;
    final tapX = _lastTapPosition?.dx ?? (tabBarOrigin.dx + 8);
    showMenu<String>(
      context: ctx,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      position: RelativeRect.fromLTRB(tapX - 8, tabBarBottom, tapX + 200, 0),
      items: [
        PopupMenuItem(value: 'panel', height: 40, child: _MenuItem(icon: Icons.vertical_align_bottom_rounded, label: 'Move to panel')),
        PopupMenuItem(value: 'close', height: 40, child: _MenuItem(icon: Icons.close, label: 'Close terminal')),
      ],
    ).then((val) {
      if (!mounted) return;
      final idx = term.sessions.indexWhere((s) => s.id == sessionId);
      if (val == 'panel') term.unpinFromTopBar(sessionId);
      if (val == 'close' && idx != -1) term.closeSession(idx);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<EditorProvider, TerminalProvider>(
      builder: (ctx, editor, term, _) {
        final topFiles = editor.topFiles;
        final topTerms = term.topBarSessions;
        final totalLen = topFiles.length + topTerms.length;

        if (totalLen == 0) return const SizedBox.shrink();

        // Compute active tab index across files + terminals
        int activeIdx = 0;
        if (term.isTopBarTerminalActive && term.topBarActiveId != null) {
          final termIdx = topTerms.indexWhere((s) => s.id == term.topBarActiveId);
          if (termIdx >= 0) {
            activeIdx = topFiles.length + termIdx;
          }
        } else {
          final topActive = editor.topActiveFile;
          final activeTop = topActive == null ? -1 : topFiles.indexOf(topActive);
          activeIdx = activeTop < 0 ? 0 : activeTop;
        }

        _syncController(totalLen, activeIdx);

        final cs = Theme.of(context).colorScheme;

        return DragTarget<Object>(
          onWillAcceptWithDetails: (details) =>
              details.data is OpenFile || details.data is TerminalSession,
          onAcceptWithDetails: (details) {
            if (details.data is OpenFile) {
              final f = details.data as OpenFile;
              final globalIndex = editor.openFiles.indexOf(f);
              if (globalIndex != -1) {
                editor.moveToPanel(globalIndex, bottom: false);
              }
            } else if (details.data is TerminalSession) {
              final s = details.data as TerminalSession;
              term.pinToTopBar(s.id);
            }
          },
          builder: (ctx2, candidates, _) {
            final isDragOver = candidates.isNotEmpty &&
                candidates.any((c) => c is OpenFile || c is TerminalSession);
            return ColoredBox(
              color: isDragOver
                  ? cs.primaryContainer.withValues(alpha: 0.3)
                  : cs.surface,
              child: Listener(
                onPointerDown: (e) => _lastTapPosition = e.position,
                child: TabBar(
                controller: _ctrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                dividerColor: Colors.transparent,
                padding: EdgeInsets.zero,
                labelPadding: EdgeInsets.zero,
                labelColor: cs.primary,
                unselectedLabelColor: cs.onSurfaceVariant,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                unselectedLabelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
                indicator: UnderlineTabIndicator(
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                onTap: (i) {
                  if (_closeHandled) return;
                  if (i < topFiles.length) {
                    // File tab tapped
                    final globalIndex = editor.openFiles.indexOf(topFiles[i]);
                    if (i == activeIdx && !term.isTopBarTerminalActive) {
                      _showFileMenu(ctx, editor, globalIndex);
                    } else {
                      term.clearTopBarActive();
                      editor.switchTo(globalIndex);
                    }
                  } else {
                    // Terminal tab tapped
                    final termLocal = i - topFiles.length;
                    final session = topTerms[termLocal];
                    if (i == activeIdx && term.isTopBarTerminalActive) {
                      _showTerminalMenu(ctx, term, session.id);
                    } else {
                      term.setTopBarActive(session.id);
                    }
                  }
                },
                tabs: [
                  // File tabs
                  for (var i = 0; i < topFiles.length; i++) ...[
                    () {
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
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Text(f.name,
                                  style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12, fontWeight: FontWeight.w600)),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.4,
                            child: _FileTabContent(file: f, cs: cs, onClose: () {}, closeHandled: false),
                          ),
                          child: _FileTabContent(
                            file: f,
                            cs: cs,
                            onClose: () {
                              _closeHandled = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) => _closeHandled = false);
                              editor.closeFile(globalIndex);
                            },
                            closeHandled: _closeHandled,
                          ),
                        ),
                      );
                    }(),
                  ],
                  // Terminal tabs
                  for (final session in topTerms) ...[
                    Tab(
                      height: 38,
                      child: _TerminalTabContent(
                        session: session,
                        cs: cs,
                        onClose: () {
                          _closeHandled = true;
                          WidgetsBinding.instance.addPostFrameCallback((_) => _closeHandled = false);
                          final idx = term.sessions.indexWhere((s) => s.id == session.id);
                          if (idx != -1) term.closeSession(idx);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              ), // Listener
            );
          },
        );
      },
    );
  }
}

class _FileTabContent extends StatelessWidget {
  final OpenFile file;
  final ColorScheme cs;
  final VoidCallback onClose;
  final bool closeHandled;

  const _FileTabContent({
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
              decoration: BoxDecoration(color: cs.error, shape: BoxShape.circle),
            ),
          Text(file.name),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Icon(Icons.close_rounded, size: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _TerminalTabContent extends StatelessWidget {
  final dynamic session; // TerminalSession
  final ColorScheme cs;
  final VoidCallback onClose;

  const _TerminalTabContent({
    required this.session,
    required this.cs,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal_rounded, size: 13, color: cs.tertiary),
          const SizedBox(width: 6),
          Text(session.label as String? ?? 'Terminal'),
          const SizedBox(width: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Icon(Icons.close_rounded, size: 13, color: cs.onSurfaceVariant),
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
