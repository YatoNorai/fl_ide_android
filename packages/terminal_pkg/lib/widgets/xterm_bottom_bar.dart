import 'package:flutter/material.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

/// Extra-keys bar shown below the terminal.
/// Tap the pill handle to collapse/expand the two rows.
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
  late final AnimationController _ctrl;
  late final Animation<double> _height;
  bool _collapsed = false;

  static const _expandedHeight = 88.0;
  static const _collapsedHeight = 22.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _height = Tween<double>(begin: _expandedHeight, end: _collapsedHeight)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _height.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    _collapsed ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: _height.value,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
        border: Border(
          top: BorderSide(
            color: colors.outline.withValues(alpha: 0.15),
          ),
        ),
      ),
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle / collapse toggle ──────────────────────────
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              child: SizedBox(
                height: 20,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: _collapsed ? 32 : 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colors.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),

            // ── Row 1 ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _Key('ESC',  () => widget.terminal.keyInput(TerminalKey.escape)),
                  _Key('TAB',  () => widget.terminal.keyInput(TerminalKey.tab)),
                  _Key('CTRL', () => widget.terminal.keyInput(TerminalKey.control)),
                  _Key('ALT',  () {}),
                  _Key('HOME', () => widget.terminal.keyInput(TerminalKey.home)),
                  _Key('↑',    () => widget.terminal.keyInput(TerminalKey.arrowUp)),
                  _Key('PGUP', () => widget.terminal.keyInput(TerminalKey.pageUp)),
                ],
              ),
            ),

            // ── Row 2 ──────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  _Key('INS',  () => widget.terminal.keyInput(TerminalKey.insert)),
                  _Key('END',  () => widget.terminal.keyInput(TerminalKey.end)),
                  _Key('SHFT', () {}),
                  _Key('PGDN', () => widget.terminal.keyInput(TerminalKey.pageDown)),
                  _Key('←',    () => widget.terminal.keyInput(TerminalKey.arrowLeft)),
                  _Key('↓',    () => widget.terminal.keyInput(TerminalKey.arrowDown)),
                  _Key('→',    () => widget.terminal.keyInput(TerminalKey.arrowRight)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Individual key chip ───────────────────────────────────────────────────────

class _Key extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _Key(this.label, this.onTap);

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          widget.onTap();
          setState(() => _pressed = true);
          Feedback.forLongPress(context);
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: _pressed
                ? colors.primary.withValues(alpha: 0.25)
                : colors.surfaceTint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _pressed
                  ? colors.primary.withValues(alpha: 0.5)
                  : colors.outline.withValues(alpha: 0.15),
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: _pressed
                    ? colors.primary
                    : colors.onSurface.withValues(alpha: 0.75),
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
