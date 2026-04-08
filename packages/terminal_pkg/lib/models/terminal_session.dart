import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

/// PTY session: flutter_pty (true PTY) + xterm 4.x rendering.
/// Supports two backends: local PTY (via [start]) or remote stream ([attachRemote]).
class TerminalSession {
  final String id;
  final String label;

  late final Terminal terminal;
  Pty? _pty;
  Pty? get pty => _pty;

  // Remote (SSH) backend
  StreamSink<List<int>>? _remoteSink;
  void Function(int w, int h)? _onRemoteResize;

  // Stream subscriptions — stored so they can be cancelled on kill()
  StreamSubscription<String>? _outputSub;
  StreamSubscription<String>? _remoteSub;

  bool _isAlive = false;
  bool get isAlive => _isAlive;
  bool get isRemote => _remoteSink != null;

  void Function(int exitCode)? onExit;

  TerminalSession({required this.id, required this.label}) {
    terminal = Terminal(
      // 3000 lines ≈ 300KB RAM per session vs 1MB for 10000 — adequate for
      // most build output and interactive use on a memory-constrained device.
      maxLines: 3000,
      onOutput: (data) {
        final bytes = const Utf8Encoder().convert(data);
        if (_remoteSink != null) {
          _remoteSink!.add(bytes);
        } else {
          _pty?.write(bytes);
        }
      },
      onResize: (w, h, pw, ph) {
        if (_onRemoteResize != null) {
          _onRemoteResize!(w, h);
        } else {
          _pty?.resize(h, w);
        }
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

    _outputSub = _pty!.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(terminal.write);

    _pty!.exitCode.then((code) {
      _isAlive = false;
      terminal.write('\r\n\x1b[33m[Process exited with code $code]\x1b[0m\r\n');
      onExit?.call(code);
    });
  }

  /// Attach a remote I/O backend (e.g. SSH shell) to this terminal session.
  /// Call instead of [start] for SSH-backed sessions.
  void attachRemote({
    required Stream<List<int>> remoteOutput,
    required StreamSink<List<int>> remoteInput,
    Future? doneFuture,
    void Function(int w, int h)? onResize,
  }) {
    _remoteSink = remoteInput;
    _onRemoteResize = onResize;
    _isAlive = true;

    _remoteSub = remoteOutput
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          terminal.write,
          onError: (_) {
            // SSH stream error (e.g. network drop while screen off).
            // Swallow here — doneFuture / onExit handles cleanup below.
          },
          cancelOnError: true,
        );

    doneFuture?.then((_) {
      _isAlive = false;
      terminal.write('\r\n\x1b[33m[SSH session ended]\x1b[0m\r\n');
      onExit?.call(0);
    }).catchError((_) {
      // doneFuture itself may complete with an error on abrupt disconnect.
      _isAlive = false;
      terminal.write('\r\n\x1b[31m[SSH connection lost]\x1b[0m\r\n');
      onExit?.call(1);
    });
  }

  /// Write a command string followed by Enter.
  /// SSH PTY expects \r (carriage return) as the Enter key;
  /// local PTY uses \n (line feed).
  void writeCommand(String cmd) {
    final terminator = _remoteSink != null ? '\r' : '\n';
    final bytes = const Utf8Encoder().convert('$cmd$terminator');
    if (_remoteSink != null) {
      _remoteSink!.add(bytes);
    } else {
      _pty?.write(bytes);
    }
  }

  void kill() {
    _outputSub?.cancel();
    _outputSub = null;
    _remoteSub?.cancel();
    _remoteSub = null;
    _remoteSink?.close();
    _remoteSink = null;
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
