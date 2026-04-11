import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'dap_client_base.dart';

/// DAP client that communicates over a TCP socket instead of stdin/stdout.
///
/// Used for adapters like Delve (Go) that start a TCP DAP server and print
/// the listening address to stderr:
///   `DAP server listening at: 127.0.0.1:<port>`
///
/// Usage:
///   1. Start the adapter process externally (or let [connectToProcess] do it).
///   2. Call [connect] with host + port.
///   3. Use [sendRequest] / [events] exactly like [DapStdioClient].
class DapTcpClient implements DapClientBase {
  Socket? _socket;
  int _seq = 0;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final StreamController<Map<String, dynamic>> _events =
      StreamController.broadcast();

  final List<int> _buf = [];
  int? _expectedLength;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isRunning => _socket != null;
  bool get isConnected => isRunning;

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<void> connect(String host, int port) async {
    _socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 8),
    );
    _socket!.listen(
      _onBytes,
      onDone: _onSocketDone,
      onError: (e) {
        debugPrint('[DAP TCP] socket error: $e');
        _onSocketDone();
      },
    );
  }

  // ── Disconnect ─────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    try { await _socket?.close(); } catch (_) {}
    _socket = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('DAP TCP client disposed'));
    }
    _pending.clear();
    if (!_events.isClosed) await _events.close();
  }

  // ── Send ───────────────────────────────────────────────────────────────────

  @override
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
    if (_socket == null) throw StateError('DAP TCP: not connected');
    final body = jsonEncode(msg);
    final bodyBytes = utf8.encode(body);
    final header = 'Content-Length: ${bodyBytes.length}\r\n\r\n';
    final headerBytes = utf8.encode(header);
    _socket!.add(Uint8List.fromList([...headerBytes, ...bodyBytes]));
    await _socket!.flush();
  }

  // ── Receive ────────────────────────────────────────────────────────────────

  void _onBytes(List<int> chunk) {
    _buf.addAll(chunk);
    _pump();
  }

  void _pump() {
    while (true) {
      if (_expectedLength == null) {
        final headerEnd = _findHeaderEnd();
        if (headerEnd == -1) return;
        final header = utf8.decode(_buf.sublist(0, headerEnd));
        _expectedLength = _parseContentLength(header);
        _buf.removeRange(0, headerEnd + 4);
      }
      if (_buf.length < _expectedLength!) return;
      final msgBytes = _buf.sublist(0, _expectedLength!);
      _buf.removeRange(0, _expectedLength!);
      _expectedLength = null;
      try {
        final json = jsonDecode(utf8.decode(msgBytes)) as Map<String, dynamic>;
        _dispatch(json);
      } catch (e) {
        debugPrint('[DAP TCP] parse error: $e');
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
    throw FormatException('No Content-Length in DAP TCP header: $header');
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
          completer.complete((msg['body'] as Map<String, dynamic>?) ?? {});
        } else {
          completer.completeError(
            Exception(msg['message'] as String? ?? 'Request failed'),
          );
        }
      case 'event':
        if (!_events.isClosed) _events.add(msg);
      default:
        debugPrint('[DAP TCP] unknown message type: $type');
    }
  }

  void _onSocketDone() {
    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('DAP TCP connection closed'));
      }
    }
    _pending.clear();
    if (!_events.isClosed) {
      _events.add({'type': 'event', 'event': 'terminated', 'body': {}});
    }
  }
}
