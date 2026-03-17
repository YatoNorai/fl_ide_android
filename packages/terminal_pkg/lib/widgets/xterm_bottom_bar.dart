import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

/// Keyboard shortcut bar for the terminal (ported from flutter_ide_android).
/// Shows two rows of terminal keys that can be collapsed/expanded by tapping
/// the drag handle.
class XtermBottomBar extends StatefulWidget {
  const XtermBottomBar({
    super.key,
    required this.pseudoTerminal,
    required this.terminal,
  });

  final Pty pseudoTerminal;
  final Terminal terminal;

  @override
  State<XtermBottomBar> createState() => _XtermBottomBarState();
}

class _XtermBottomBarState extends State<XtermBottomBar>
    with SingleTickerProviderStateMixin {
  final Color _defaultDragColor = Colors.white.withValues(alpha: 0.4);
  late Animation<double> _height;
  late AnimationController _controller;
  late Color _dragColor;

  @override
  void initState() {
    super.initState();
    _dragColor = _defaultDragColor;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _height = Tween<double>(begin: 82.0, end: 18.0).animate(
      CurvedAnimation(curve: Curves.easeIn, parent: _controller),
    );
    _height.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _height.value,
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanDown: (_) => setState(() => _dragColor = Colors.white.withValues(alpha: 0.8)),
              onPanCancel: () => setState(() => _dragColor = _defaultDragColor),
              onPanEnd: (_) => setState(() => _dragColor = _defaultDragColor),
              onTap: () {
                if (_controller.isCompleted) {
                  _controller.reverse();
                } else {
                  _controller.forward();
                }
              },
              child: SizedBox(
                height: 16,
                child: Center(
                  child: Container(
                    width: 20,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _dragColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                _TermKey(terminal: widget.terminal, title: 'ESC',
                    onTap: () => widget.terminal.keyInput(TerminalKey.escape)),
                _TermKey(terminal: widget.terminal, title: 'TAB',
                    onTap: () => widget.terminal.keyInput(TerminalKey.tab)),
                _TermKey(terminal: widget.terminal, title: 'CTRL',
                    onTap: () => widget.terminal.keyInput(TerminalKey.control)),
                _TermKey(terminal: widget.terminal, title: 'ALT',
                    onTap: () {}),
                _TermKey(terminal: widget.terminal, title: 'HOME',
                    onTap: () => widget.terminal.keyInput(TerminalKey.home)),
                _TermKey(terminal: widget.terminal, title: '↑',
                    onTap: () => widget.terminal.keyInput(TerminalKey.arrowUp)),
                _TermKey(terminal: widget.terminal, title: 'PGUP',
                    onTap: () => widget.terminal.keyInput(TerminalKey.pageUp)),
              ],
            ),
            Row(
              children: [
                _TermKey(terminal: widget.terminal, title: 'INS',
                    onTap: () => widget.terminal.keyInput(TerminalKey.insert)),
                _TermKey(terminal: widget.terminal, title: 'END',
                    onTap: () => widget.terminal.keyInput(TerminalKey.end)),
                _TermKey(terminal: widget.terminal, title: 'SHIFT',
                    onTap: () {}),
                _TermKey(terminal: widget.terminal, title: 'PGDN',
                    onTap: () => widget.terminal.keyInput(TerminalKey.pageDown)),
                _TermKey(terminal: widget.terminal, title: '←',
                    onTap: () => widget.terminal.keyInput(TerminalKey.arrowLeft)),
                _TermKey(terminal: widget.terminal, title: '↓',
                    onTap: () => widget.terminal.keyInput(TerminalKey.arrowDown)),
                _TermKey(terminal: widget.terminal, title: '→',
                    onTap: () => widget.terminal.keyInput(TerminalKey.arrowRight)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TermKey extends StatefulWidget {
  const _TermKey({
    required this.terminal,
    required this.title,
    this.onTap,
  });

  final Terminal terminal;
  final String title;
  final VoidCallback? onTap;

  @override
  State<_TermKey> createState() => _TermKeyState();
}

class _TermKeyState extends State<_TermKey> {
  Color _backgroundColor = Colors.transparent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (_) {
          widget.onTap?.call();
          setState(() => _backgroundColor =
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.2));
          Feedback.forLongPress(context);
        },
        onPanEnd: (_) {
          setState(() => _backgroundColor = Colors.transparent);
          Feedback.forLongPress(context);
        },
        onPanCancel: () {
          setState(() => _backgroundColor = Colors.transparent);
          Feedback.forLongPress(context);
        },
        child: Container(
          decoration: BoxDecoration(color: _backgroundColor),
          height: 30,
          child: Center(
            child: Text(
              widget.title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimary,
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
