import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../models/terminal_session.dart';

const _kVsCodeDark = TerminalTheme(
  cursor:     AppTheme.darkText,
  selection:  AppTheme.darkSelection,
  foreground: AppTheme.darkText,
  background: AppTheme.darkPanel,
  black:   Color(0xFF000000),
  red:     Color(0xFFCD3131),
  green:   Color(0xFF0DBC79),
  yellow:  Color(0xFFE5E510),
  blue:    Color(0xFF2472C8),
  magenta: Color(0xFFBC3FBC),
  cyan:    Color(0xFF11A8CD),
  white:   Color(0xFFE5E5E5),
  brightBlack:   Color(0xFF666666),
  brightRed:     Color(0xFFF14C4C),
  brightGreen:   Color(0xFF23D18B),
  brightYellow:  Color(0xFFF5F543),
  brightBlue:    Color(0xFF3B8EEA),
  brightMagenta: Color(0xFFD670D6),
  brightCyan:    Color(0xFF29B8DB),
  brightWhite:   Color(0xFFFFFFFF),
  searchHitBackground:        Color(0xFFFFFF00),
  searchHitBackgroundCurrent: Color(0xFFFF8C00),
  searchHitForeground:        Color(0xFF000000),
);

class PtyTerminalWidget extends StatelessWidget {
  final TerminalSession session;

  const PtyTerminalWidget({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return TerminalView(
      session.terminal,
      theme: _kVsCodeDark,
      autofocus: true,
      padding: const EdgeInsets.all(4),
    );
  }
}
