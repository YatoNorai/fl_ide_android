import 'package:flutter/material.dart';

// ── Log priority level ────────────────────────────────────────────────────────

enum LogLevel { verbose, debug, info, warning, error, fatal, system, unknown }

// ── Log line model ────────────────────────────────────────────────────────────

class LogLine {
  final String date;
  final String time;
  final String pid;
  final String tid;
  final LogLevel level;
  final String tag;
  final String message;

  /// Raw text — shown as a dim system/separator line when [level] == system.
  final String raw;

  const LogLine({
    required this.date,
    required this.time,
    required this.pid,
    required this.tid,
    required this.level,
    required this.tag,
    required this.message,
    required this.raw,
  });

  /// Creates a non-parsed system/separator line (e.g. "--- app started ---").
  const LogLine.system(String text)
      : date = '',
        time = '',
        pid = '',
        tid = '',
        level = LogLevel.system,
        tag = '',
        message = text,
        raw = text;

  // ── Parser ──────────────────────────────────────────────────────────────────

  /// Matches `adb logcat -v threadtime` output:
  ///   `MM-DD HH:MM:SS.mmm  PID   TID  L  TAG    : message`
  static final _rx = RegExp(
    r'^(\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2}\.\d+)\s+(\d+)\s+(\d+)\s+'
    r'([VDIWEFS])\s+(.*?)\s*:\s(.*)$',
  );

  static LogLevel _levelFromChar(String ch) {
    switch (ch.toUpperCase()) {
      case 'V': return LogLevel.verbose;
      case 'D': return LogLevel.debug;
      case 'I': return LogLevel.info;
      case 'W': return LogLevel.warning;
      case 'E': return LogLevel.error;
      case 'F': return LogLevel.fatal;
      default:  return LogLevel.unknown;
    }
  }

  /// Returns null when the line doesn't match the threadtime format.
  static LogLine? parse(String raw) {
    if (raw.isEmpty) return null;
    final m = _rx.firstMatch(raw.trim());
    if (m == null) return null;
    return LogLine(
      date:    m.group(1)!,
      time:    m.group(2)!,
      pid:     m.group(3)!,
      tid:     m.group(4)!,
      level:   _levelFromChar(m.group(5)!),
      tag:     m.group(6)!.trim(),
      message: m.group(7)!,
      raw:     raw,
    );
  }

  // ── Colours matching AndroidIDE's SchemeAndroidIDE ───────────────────────────

  Color textColor(Brightness brightness) {
    switch (level) {
      case LogLevel.error:
      case LogLevel.fatal:
        return const Color(0xFFEF5350);   // red 400
      case LogLevel.warning:
        return const Color(0xFFFFA726);   // orange 400
      case LogLevel.info:
        return const Color(0xFF66BB6A);   // green 400
      case LogLevel.debug:
        return brightness == Brightness.dark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF424242);
      case LogLevel.verbose:
        return const Color(0xFF4FC3F7);   // light blue 300
      case LogLevel.system:
        return const Color(0xFF9E9E9E);   // grey 500
      case LogLevel.unknown:
        return brightness == Brightness.dark
            ? const Color(0xFFBDBDBD)
            : const Color(0xFF616161);
    }
  }

  Color? rowBackground(Brightness brightness) {
    switch (level) {
      case LogLevel.error:
      case LogLevel.fatal:
        return brightness == Brightness.dark
            ? const Color(0x22EF5350)
            : const Color(0x18EF5350);
      case LogLevel.warning:
        return brightness == Brightness.dark
            ? const Color(0x22FFA726)
            : const Color(0x12FFA726);
      default:
        return null;
    }
  }

  String get levelChar {
    switch (level) {
      case LogLevel.verbose: return 'V';
      case LogLevel.debug:   return 'D';
      case LogLevel.info:    return 'I';
      case LogLevel.warning: return 'W';
      case LogLevel.error:   return 'E';
      case LogLevel.fatal:   return 'F';
      default:               return '-';
    }
  }
}
