import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../models/terminal_session.dart';

enum _TerminalAction { copy, copyAll, paste }

class PtyTerminalWidget extends StatefulWidget {
  final TerminalSession session;

  const PtyTerminalWidget({super.key, required this.session});

  @override
  State<PtyTerminalWidget> createState() => _PtyTerminalWidgetState();
}

class _PtyTerminalWidgetState extends State<PtyTerminalWidget> {
  late final TerminalController _ctrl;

  // ── Theme cache — keyed by (brightness ^ primary ^ surface) ─────────────
  static int? _lightKey;
  static int? _darkKey;
  static TerminalTheme? _lightTheme;
  static TerminalTheme? _darkTheme;

  static TerminalTheme _themeFor(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    final key = cs.primary.toARGB32() ^ cs.surface.toARGB32();
    if (isDark && _darkTheme != null && _darkKey == key) return _darkTheme!;
    if (!isDark && _lightTheme != null && _lightKey == key) return _lightTheme!;
    final theme = TerminalTheme(
      cursor:     cs.primary,
      selection:  cs.primary.withValues(alpha: 0.35),
      foreground: cs.onSurface,
      background: cs.surface,
      black:   isDark ? const Color(0xFF1E1E1E) : const Color(0xFF000000),
      red:     const Color(0xFFCD3131),
      green:   const Color(0xFF0DBC79),
      yellow:  const Color(0xFFE5E510),
      blue:    const Color(0xFF2472C8),
      magenta: const Color(0xFFBC3FBC),
      cyan:    const Color(0xFF11A8CD),
      white:   isDark ? const Color(0xFFE5E5E5) : const Color(0xFF555555),
      brightBlack:   const Color(0xFF666666),
      brightRed:     const Color(0xFFF14C4C),
      brightGreen:   const Color(0xFF23D18B),
      brightYellow:  const Color(0xFFF5F543),
      brightBlue:    const Color(0xFF3B8EEA),
      brightMagenta: const Color(0xFFD670D6),
      brightCyan:    const Color(0xFF29B8DB),
      brightWhite:   const Color(0xFFFFFFFF),
      searchHitBackground:        const Color(0xFFFFFF00),
      searchHitBackgroundCurrent: const Color(0xFFFF8C00),
      searchHitForeground:        const Color(0xFF000000),
    );
    if (isDark) { _darkTheme = theme; _darkKey = key; }
    else { _lightTheme = theme; _lightKey = key; }
    return theme;
  }

  @override
  void initState() {
    super.initState();
    _ctrl = TerminalController();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Context menu ──────────────────────────────────────────────────────────

  Future<void> _showContextMenu(BuildContext ctx, Offset globalPos) async {
    HapticFeedback.mediumImpact();

    // Try to read any currently selected text via the controller.
    final selRange = _ctrl.selection;
    final selectedText = selRange != null
        ? widget.session.terminal.buffer.getText(selRange)
        : null;
    final hasSelection =
        selectedText != null && selectedText.trim().isNotEmpty;

    final RenderBox? overlay =
        Overlay.of(ctx).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final action = await showMenu<_TerminalAction>(
      context: ctx,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        if (hasSelection)
          PopupMenuItem<_TerminalAction>(
            value: _TerminalAction.copy,
            child: _MenuRow(Icons.copy_rounded, 'Copiar seleção'),
          ),
        PopupMenuItem<_TerminalAction>(
          value: _TerminalAction.paste,
          child: _MenuRow(Icons.content_paste_rounded, 'Colar'),
        ),
        PopupMenuItem<_TerminalAction>(
          value: _TerminalAction.copyAll,
          child: _MenuRow(Icons.select_all_rounded, 'Copiar tudo'),
        ),
      ],
    );

    if (!mounted || action == null) return;

    switch (action) {
      case _TerminalAction.copy:
        if (hasSelection) {
          await Clipboard.setData(ClipboardData(text: selectedText));
          _ctrl.clearSelection();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Copiado'),
                duration: Duration(seconds: 1),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        }

      case _TerminalAction.paste:
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text;
        if (text != null && text.isNotEmpty) {
          // Use terminal.textInput so the existing onOutput pipeline
          // (including the XtermBottomBar modifier interceptor) handles
          // the bytes correctly, just like soft-keyboard input.
          widget.session.terminal.textInput(text);
        }

      case _TerminalAction.copyAll:
        final all = widget.session.terminal.buffer.getText();
        await Clipboard.setData(ClipboardData(text: all));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Saída completa copiada'),
              duration: Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return RepaintBoundary(
      child: GestureDetector(
        // Long-press shows the copy/paste context menu.
        // HitTestBehavior.deferToChild lets the TerminalView receive its
        // own tap / drag / scroll events normally; only long-press is
        // intercepted here.
        behavior: HitTestBehavior.deferToChild,
        onLongPressStart: (d) => _showContextMenu(context, d.globalPosition),
        child: TerminalView(
          widget.session.terminal,
          controller: _ctrl,
          theme: _themeFor(cs),
          autofocus: false,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          deleteDetection: true,
        ),
      ),
    );
  }
}

// ── Small helper for menu rows ────────────────────────────────────────────────

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.onSurfaceVariant),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}
