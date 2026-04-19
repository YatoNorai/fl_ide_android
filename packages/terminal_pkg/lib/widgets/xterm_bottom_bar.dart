import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../models/terminal_session.dart';

// ── Full-size bottom key bar ──────────────────────────────────────────────────

/// Extra-keys bar shown below the terminal.
/// Tap the pill handle to collapse/expand the two rows.
///
/// CTRL and ALT are **sticky**: a single tap latches them in the highlighted
/// state and they stay active until the next key press (from this bar or from
/// the soft keyboard).  This mirrors PC behaviour — press Ctrl, then type 'c'
/// on the soft keyboard to send Ctrl+C (0x03).
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
  late final AnimationController _animCtrl;
  late final Animation<double> _height;
  bool _collapsed = false;

  // ── Sticky modifier state ──────────────────────────────────────────────
  bool _ctrlActive  = false;
  bool _altActive   = false;
  bool _shiftActive = false;

  /// Original terminal.onOutput saved so we can restore it on dispose.
  void Function(String)? _savedOnOutput;

  static const _expandedHeight  = 88.0;
  static const _collapsedHeight = 22.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _height = Tween<double>(begin: _expandedHeight, end: _collapsedHeight)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut));
    // Removido: _height.addListener(() => setState(() {}))
    // O AnimatedBuilder no build() escuta a animação e reconstrói
    // apenas o SizedBox de altura, sem rebuildar o widget inteiro.
    _installInterceptor(widget.terminal);
  }

  @override
  void didUpdateWidget(XtermBottomBar old) {
    super.didUpdateWidget(old);
    if (old.terminal != widget.terminal) {
      _removeInterceptor(old.terminal);
      _ctrlActive = false;
      _altActive = false;
      _shiftActive = false;
      _installInterceptor(widget.terminal);
    }
  }

  @override
  void dispose() {
    _removeInterceptor(widget.terminal);
    _animCtrl.dispose();
    super.dispose();
  }

  void _installInterceptor(Terminal terminal) {
    _savedOnOutput = terminal.onOutput;
    terminal.onOutput = _interceptOutput;
  }

  void _removeInterceptor(Terminal terminal) {
    if (terminal.onOutput == _interceptOutput) {
      terminal.onOutput = _savedOnOutput;
    }
  }

  // ── Soft-keyboard input interception ──────────────────────────────────
  //
  // When a modifier is latched and the user types a character on the soft
  // keyboard, terminal.onOutput is called with the raw character string.
  // We intercept here and convert to the correct escape / control sequence.
  void _interceptOutput(String data) {
    if (data.length == 1) {
      final code = data.codeUnitAt(0);

      // CTRL: convert printable ASCII [0x20–0x7E] → control codes [0x00–0x1E]
      if (_ctrlActive && code >= 0x20 && code <= 0x7E) {
        _clearModifiers();
        _savedOnOutput?.call(String.fromCharCode(code & 0x1F));
        return;
      }

      // ALT: prefix with ESC (standard terminal alt-sequence)
      if (_altActive && code >= 0x20) {
        _clearModifiers();
        _savedOnOutput?.call('\x1b$data');
        return;
      }
    }

    // Any other input (multi-char, escape sequences, non-ASCII) — clear
    // the pending modifier so it doesn't accidentally fire later.
    if (_ctrlActive || _altActive || _shiftActive) _clearModifiers();
    _savedOnOutput?.call(data);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  void _clearModifiers() {
    if (!_ctrlActive && !_altActive && !_shiftActive) return;
    setState(() {
      _ctrlActive  = false;
      _altActive   = false;
      _shiftActive = false;
    });
  }

  /// Send a special key, applying any active sticky modifier, then clear it.
  void _sendKey(TerminalKey key) {
    widget.terminal.keyInput(
      key,
      ctrl:  _ctrlActive,
      alt:   _altActive,
      shift: _shiftActive,
    );
    _clearModifiers();
  }

  void _toggle() {
    setState(() => _collapsed = !_collapsed);
    _collapsed ? _animCtrl.forward() : _animCtrl.reverse();
  }

  // ── Build ──────────────────────────────────────────────────────────────

  /// Constrói o conteúdo estático (teclas + handle) que não muda por frame.
  /// Passado como `child` do AnimatedBuilder, é instanciado uma única vez
  /// e reutilizado durante toda a animação de expand/collapse.
  Widget _buildContent(ColorScheme colors) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Drag handle / collapse toggle ────────────────────────────
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

          // ── Row 1 ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                _Key('ESC',  () => _sendKey(TerminalKey.escape)),
                _Key('TAB',  () => _sendKey(TerminalKey.tab)),
                // CTRL — sticky: latches on first tap, releases after next key
                _Key('CTRL',
                  () => setState(() {
                    _ctrlActive = !_ctrlActive;
                    if (_ctrlActive) _altActive = false;
                  }),
                  active: _ctrlActive,
                ),
                // ALT — sticky
                _Key('ALT',
                  () => setState(() {
                    _altActive = !_altActive;
                    if (_altActive) _ctrlActive = false;
                  }),
                  active: _altActive,
                ),
                _Key('HOME', () => _sendKey(TerminalKey.home)),
                _Key('↑',    () => _sendKey(TerminalKey.arrowUp)),
                _Key('PGUP', () => _sendKey(TerminalKey.pageUp)),
              ],
            ),
          ),

          // ── Row 2 ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                _Key('INS',  () => _sendKey(TerminalKey.insert)),
                _Key('END',  () => _sendKey(TerminalKey.end)),
                // SHFT — sticky
                _Key('SHFT',
                  () => setState(() => _shiftActive = !_shiftActive),
                  active: _shiftActive,
                ),
                _Key('PGDN', () => _sendKey(TerminalKey.pageDown)),
                _Key('←',    () => _sendKey(TerminalKey.arrowLeft)),
                _Key('↓',    () => _sendKey(TerminalKey.arrowDown)),
                _Key('→',    () => _sendKey(TerminalKey.arrowRight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // AnimatedBuilder escuta apenas _height. O parâmetro `child` é construído
    // uma única vez fora do builder e repassado pronto — evita rebuildar as
    // linhas de teclas (Row + _Key widgets) a cada frame da animação (60 fps).
    return AnimatedBuilder(
      animation: _height,
      builder: (context, child) {
        return Container(
          height: _height.value,
          decoration: BoxDecoration(
            color: colors.surfaceContainerHighest.withValues(alpha: 0.6),
            border: Border(
              top: BorderSide(color: colors.outline.withValues(alpha: 0.15)),
            ),
          ),
          child: child,
        );
      },
      child: _buildContent(colors),
    );
  }
}

// ── Compact single-row key bar for the mini terminal ─────────────────────────

/// A compact single-row key bar for the mini terminal in the bottom sheet.
///
/// Shows the essential terminal keys in a space-efficient layout.
/// CTRL and ALT are **sticky** — same behaviour as [XtermBottomBar].
class MiniTerminalKeyBar extends StatefulWidget {
  const MiniTerminalKeyBar({
    super.key,
    required this.session,
    this.liquidGlass = false,
  });

  final TerminalSession session;
  final bool liquidGlass;

  @override
  State<MiniTerminalKeyBar> createState() => _MiniTerminalKeyBarState();
}

class _MiniTerminalKeyBarState extends State<MiniTerminalKeyBar> {
  bool _ctrlActive  = false;
  bool _altActive   = false;
  bool _shiftActive = false;

  void Function(String)? _savedOnOutput;

  @override
  void initState() {
    super.initState();
    _installInterceptor(widget.session.terminal);
  }

  @override
  void didUpdateWidget(MiniTerminalKeyBar old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      _removeInterceptor(old.session.terminal);
      _ctrlActive = false;
      _altActive = false;
      _shiftActive = false;
      _installInterceptor(widget.session.terminal);
    }
  }

  @override
  void dispose() {
    _removeInterceptor(widget.session.terminal);
    super.dispose();
  }

  void _installInterceptor(Terminal terminal) {
    _savedOnOutput = terminal.onOutput;
    terminal.onOutput = _interceptOutput;
  }

  void _removeInterceptor(Terminal terminal) {
    if (terminal.onOutput == _interceptOutput) {
      terminal.onOutput = _savedOnOutput;
    }
  }

  void _interceptOutput(String data) {
    if (data.length == 1) {
      final code = data.codeUnitAt(0);
      if (_ctrlActive && code >= 0x20 && code <= 0x7E) {
        _clearModifiers();
        _savedOnOutput?.call(String.fromCharCode(code & 0x1F));
        return;
      }
      if (_altActive && code >= 0x20) {
        _clearModifiers();
        _savedOnOutput?.call('\x1b$data');
        return;
      }
    }
    if (_ctrlActive || _altActive || _shiftActive) _clearModifiers();
    _savedOnOutput?.call(data);
  }

  void _clearModifiers() {
    if (!_ctrlActive && !_altActive && !_shiftActive) return;
    setState(() {
      _ctrlActive  = false;
      _altActive   = false;
      _shiftActive = false;
    });
  }

  void _sendKey(TerminalKey key) {
    widget.session.terminal.keyInput(
      key,
      ctrl:  _ctrlActive,
      alt:   _altActive,
      shift: _shiftActive,
    );
    _clearModifiers();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: widget.liquidGlass ? Colors.transparent : cs.surfaceContainerHighest.withValues(alpha: 0.55),
        border: Border(
          top: BorderSide(color: widget.liquidGlass ? Colors.transparent : cs.outline.withValues(alpha: 0.13)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          children: [
            _MiniKey('ESC',  () => _sendKey(TerminalKey.escape)),
            _MiniKey('TAB',  () => _sendKey(TerminalKey.tab)),
            _MiniKey('CTRL',
              () => setState(() {
                _ctrlActive = !_ctrlActive;
                if (_ctrlActive) _altActive = false;
              }),
              active: _ctrlActive,
            ),
            _MiniKey('ALT',
              () => setState(() {
                _altActive = !_altActive;
                if (_altActive) _ctrlActive = false;
              }),
              active: _altActive,
            ),
            _MiniKey('SHFT',
              () => setState(() => _shiftActive = !_shiftActive),
              active: _shiftActive,
            ),
            _MiniKey('←', () => _sendKey(TerminalKey.arrowLeft)),
            _MiniKey('↑', () => _sendKey(TerminalKey.arrowUp)),
            _MiniKey('↓', () => _sendKey(TerminalKey.arrowDown)),
            _MiniKey('→', () => _sendKey(TerminalKey.arrowRight)),
          ],
        ),
      ),
    );
  }
}

// ── Key widgets ───────────────────────────────────────────────────────────────

/// A key chip for [XtermBottomBar].
/// Pass [active] = true to keep the chip highlighted (for sticky modifiers).
class _Key extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _Key(this.label, this.onTap, {this.active = false});

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lit = widget.active || _pressed;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          widget.onTap();
          setState(() => _pressed = true);
          HapticFeedback.lightImpact();
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 32,
          margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: BoxDecoration(
            color: lit
                ? cs.primary.withValues(alpha: 0.22)
                : cs.surfaceTint.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: lit
                  ? cs.primary.withValues(alpha: 0.55)
                  : cs.outline.withValues(alpha: 0.15),
              width: lit ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: lit
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.75),
                fontWeight:
                    widget.active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 11,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A smaller key chip for [MiniTerminalKeyBar].
class _MiniKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  final bool active;
  const _MiniKey(this.label, this.onTap, {this.active = false});

  @override
  State<_MiniKey> createState() => _MiniKeyState();
}

class _MiniKeyState extends State<_MiniKey> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lit = widget.active || _pressed;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) {
          widget.onTap();
          setState(() => _pressed = true);
          HapticFeedback.lightImpact();
        },
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: 28,
          margin: const EdgeInsets.symmetric(horizontal: 1.5),
          decoration: BoxDecoration(
            color: lit
                ? cs.primary.withValues(alpha: 0.2)
                : cs.surfaceTint.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: lit
                  ? cs.primary.withValues(alpha: 0.45)
                  : cs.outline.withValues(alpha: 0.12),
              width: lit ? 1.5 : 1.0,
            ),
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color: lit
                    ? cs.primary
                    : cs.onSurface.withValues(alpha: 0.7),
                fontWeight:
                    widget.active ? FontWeight.w700 : FontWeight.w500,
                fontSize: 10,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
