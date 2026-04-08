import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

/// Low-level DAP stdio client.
///
/// Handles Content-Length framing (same as LSP), request/response matching
/// via sequence numbers, and exposes an event stream for DAP events.
class DapStdioClient {
  Process? _process;
  // For SSH-backed sessions: write to this sink instead of _process.stdin
  // dartssh2 SSHSession.stdin is StreamSink<Uint8List>.
  StreamSink<Uint8List>? _remoteSink;

  int _seq = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController.broadcast();

  // Buffer for partial reads
  final List<int> _buf = [];
  int? _expectedLength;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get isRunning => _process != null || _remoteSink != null;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  Future<void> start(
    String executable,
    List<String> args,
    Map<String, String> env, {
    void Function(String line)? onStderr,
  }) async {
    _process = await Process.start(
      executable,
      args,
      environment: env,
      runInShell: true,
    );

    _process!.stdout.listen(_onBytes, onDone: _onProcessDone);
    _process!.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          debugPrint('[DAP stderr] $line');
          onStderr?.call(line);
        });
    _process!.exitCode.then((_) => _onProcessDone());
  }

  /// Attach to an SSH-backed remote process.
  /// [remoteStdout] / [remoteStdin] are the SSH session's stdio streams
  /// (dartssh2 uses Stream<Uint8List> / StreamSink<Uint8List>).
  Future<void> startRemote(
    Stream<Uint8List> remoteStdout,
    StreamSink<Uint8List> remoteStdin, {
    void Function(String line)? onStderr,
  }) async {
    _remoteSink = remoteStdin;
    remoteStdout.listen(_onBytes, onDone: _onProcessDone);
  }

  Future<void> dispose() async {
    _remoteSink = null;
    _process?.kill();
    _process = null;
    for (final c in _pending.values) {
      c.completeError(StateError('DAP client disposed'));
    }
    _pending.clear();
    if (!_events.isClosed) await _events.close();
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  /// Sends a DAP request and returns the response body map.
  /// Throws [DapException] on failure responses.
  Future<Map<String, dynamic>> sendRequest(
    String command, [
    Map<String, dynamic>? arguments,
  ]) async {
    final seq = ++_seq;
    final msg = <String, dynamic>{
      'seq': seq,
      'type': 'request',
      'command': command,
      if (arguments != null) 'arguments': arguments,
    };
    await _sendRaw(msg);

    final completer = Completer<Map<String, dynamic>>();
    _pending[seq] = completer;
    return completer.future;
  }

  Future<void> _sendRaw(Map<String, dynamic> msg) async {
    final body = jsonEncode(msg);
    final bytes = utf8.encode(body);
    final header = utf8.encode('Content-Length: ${bytes.length}\r\n\r\n');
    final framed = Uint8List.fromList([...header, ...bytes]);
    if (_remoteSink != null) {
      _remoteSink!.add(framed);
    } else if (_process != null) {
      _process!.stdin.add(header);
      _process!.stdin.add(bytes);
      await _process!.stdin.flush();
    }
  }

  // ── Receive ────────────────────────────────────────────────────────────────

  void _onBytes(List<int> chunk) {
    _buf.addAll(chunk);
    _pump();
  }

  void _pump() {
    while (true) {
      if (_expectedLength == null) {
        // Look for \r\n\r\n header terminator
        final headerEnd = _findHeaderEnd();
        if (headerEnd == -1) return;
        final header = utf8.decode(_buf.sublist(0, headerEnd));
        _expectedLength = _parseContentLength(header);
        _buf.removeRange(0, headerEnd + 4); // +4 for \r\n\r\n
      }

      if (_buf.length < _expectedLength!) return;

      final msgBytes = _buf.sublist(0, _expectedLength!);
      _buf.removeRange(0, _expectedLength!);
      _expectedLength = null;

      try {
        final json = jsonDecode(utf8.decode(msgBytes)) as Map<String, dynamic>;
        _dispatch(json);
      } catch (e) {
        debugPrint('[DAP] parse error: $e');
      }
    }
  }

  int _findHeaderEnd() {
    for (int i = 0; i < _buf.length - 3; i++) {
      if (_buf[i] == 0x0D &&
          _buf[i + 1] == 0x0A &&
          _buf[i + 2] == 0x0D &&
          _buf[i + 3] == 0x0A) return i;
    }
    return -1;
  }

  int _parseContentLength(String header) {
    for (final line in header.split('\r\n')) {
      if (line.toLowerCase().startsWith('content-length:')) {
        return int.parse(line.split(':')[1].trim());
      }
    }
    throw FormatException('No Content-Length in DAP header: $header');
  }

  void _dispatch(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;
    switch (type) {
      case 'response':
        final requestSeq = msg['request_seq'] as int?;
        if (requestSeq == null) return;
        final completer = _pending.remove(requestSeq);
        if (completer == null) return;
        final success = msg['success'] as bool? ?? false;
        if (success) {
          completer.complete(
              (msg['body'] as Map<String, dynamic>?) ?? {});
        } else {
          completer.completeError(
            DapException(msg['message'] as String? ?? 'Request failed'),
          );
        }
      case 'event':
        if (!_events.isClosed) _events.add(msg);
      default:
        debugPrint('[DAP] unknown message type: $type');
    }
  }

  void _onProcessDone() {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('DAP process exited'));
      }
    }
    _pending.clear();
    if (!_events.isClosed) {
      _events.add({'type': 'event', 'event': 'terminated', 'body': {}});
    }
  }
}

class DapException implements Exception {
  final String message;
  const DapException(this.message);
  @override
  String toString() => 'DapException: $message';
}
