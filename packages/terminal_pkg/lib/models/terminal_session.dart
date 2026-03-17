import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

/// PTY session: flutter_pty (true PTY) + xterm 4.x rendering.
class TerminalSession {
  final String id;
  final String label;

  late final Terminal terminal;
  Pty? _pty;
  Pty? get pty => _pty;

  bool _isAlive = false;
  bool get isAlive => _isAlive;

  void Function(int exitCode)? onExit;

  TerminalSession({required this.id, required this.label}) {
    // xterm 4.x: use onOutput callback (not stream)
    terminal = Terminal(
      maxLines: 10000,
      onOutput: (data) {
        // User typed in terminal → send raw bytes to PTY stdin
        _pty?.write(const Utf8Encoder().convert(data));
      },
      onResize: (w, h, pw, ph) {
        _pty?.resize(h, w);
      },
    );
  }

  Future<void> start({
    String? executable,
    List<String> arguments = const [],
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final shell = executable ?? _defaultShell();
    final env = {
      ...RuntimeEnvir.baseEnv,
      if (environment != null) ...environment,
    };
    final workDir = workingDirectory ?? RuntimeEnvir.homePath;

    _pty = Pty.start(
      shell,
      arguments: arguments,
      environment: env,
      workingDirectory:
          Directory(workDir).existsSync() ? workDir : '/',
      rows: terminal.viewHeight,
      columns: terminal.viewWidth,
    );

    _isAlive = true;

    // PTY output → terminal.write (same pattern as termare)
    _pty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    // Exit
    _pty!.exitCode.then((code) {
      _isAlive = false;
      terminal.write('\r\n\x1b[33m[Process exited with code $code]\x1b[0m\r\n');
      onExit?.call(code);
    });
  }

  /// Write a command string (sends to PTY stdin directly, not via terminal)
  void writeCommand(String cmd) {
    _pty?.write(const Utf8Encoder().convert('$cmd\n'));
  }

  void kill() {
    _pty?.kill();
    _isAlive = false;
  }

  static String _defaultShell() {
    final rootfsBash = RuntimeEnvir.bashPath;
    if (File(rootfsBash).existsSync()) return rootfsBash;
    if (Platform.isAndroid) return '/system/bin/sh';
    if (Platform.isWindows) return 'cmd.exe';
    return '/bin/bash';
  }
}
