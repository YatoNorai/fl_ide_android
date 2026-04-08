import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/terminal_session.dart';

class PtyTerminalWidget extends StatelessWidget {
  final TerminalSession session;

  const PtyTerminalWidget({super.key, required this.session});

  /// Builds a TerminalTheme that matches the active MaterialTheme.
  /// Cached by brightness to avoid allocating a new object every build.
  static TerminalTheme? _lightTheme;
  static TerminalTheme? _darkTheme;

  static TerminalTheme _themeFor(ColorScheme cs) {
    final isDark = cs.brightness == Brightness.dark;
    if (isDark && _darkTheme != null) return _darkTheme!;
    if (!isDark && _lightTheme != null) return _lightTheme!;
    final theme = TerminalTheme(
      cursor:     cs.primary,
      selection:  cs.primary.withValues(alpha: 0.35),
      foreground: cs.onSurface,
      background: cs.surface,
      // ── Standard ANSI colours ─────────────────────────────────────────
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
    if (isDark) { _darkTheme = theme; } else { _lightTheme = theme; }
    return theme;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // RepaintBoundary isolates the terminal canvas from the rest of the UI.
    // The terminal repaints at its own rate (cursor blink, output); without
    // this boundary, its repaints would propagate up the render tree.
    return RepaintBoundary(
      child: TerminalView(
        session.terminal,
        theme: _themeFor(cs),
        autofocus: true,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      ),
    );
  }
}
