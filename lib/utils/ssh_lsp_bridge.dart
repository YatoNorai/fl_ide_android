import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

/// Local WebSocket-to-SSH-stdio bridge for running an LSP server on a
/// remote machine over SSH.
///
/// Starts an HTTP server on a free localhost port, accepts a single WebSocket
/// connection (from QuillLspSocketConfig inside QuillCodeEditor), and
/// translates between WebSocket JSON frames and LSP Content-Length framing on
/// the remote process stdio.
///
/// Usage:
/// ```dart
/// final session = await ssh.startProcess('dart language-server --lsp');
/// final bridge = await SshLspBridge.start(
///   remoteStdout: session.stdout,
///   remoteStdin: session.stdin,
/// );
/// // Wait briefly — if the process dies immediately the bridge marks itself dead.
/// await Future.delayed(const Duration(milliseconds: 500));
/// if (bridge.isAlive) {
///   lspProvider.startForSocket(bridge.wsUrl, 'dart', projectPath);
/// }
/// ```
class SshLspBridge {
  final int port;
  final HttpServer _server;
  final List<int> _buf = [];
  WebSocket? _ws;
  bool _closed = false;

  // True while the remote LSP process is producing output.
  // Set to false on stdout onDone / error.  Does NOT close the HTTP server —
  // that only happens in close() so QuillCodeEditor never gets "Connection
  // refused" due to a race between process exit and WS connect.
  bool _processAlive = true;

  SshLspBridge._({required this.port, required HttpServer server})
      : _server = server;

  /// WebSocket URL to pass to [QuillLspSocketConfig].
  String get wsUrl => 'ws://127.0.0.1:$port';

  /// True while the remote LSP process is alive and the bridge has not been
  /// explicitly closed.  Check this after a short delay to skip [startForSocket]
  /// when the process exits immediately (command not found, etc.).
  bool get isAlive => _processAlive && !_closed;

  /// Start the bridge. [remoteStdout] and [remoteStdin] are the stdio streams
  /// of the SSH-executed LSP process (dartssh2 uses Uint8List).
  static Future<SshLspBridge> start({
    required Stream<Uint8List> remoteStdout,
    required StreamSink<Uint8List> remoteStdin,
  }) async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final bridge = SshLspBridge._(port: server.port, server: server);

    // Pipe remote LSP stdout → parse Content-Length frames → WS messages.
    // IMPORTANT: do NOT call bridge.close() on onDone — the HTTP server must
    // stay alive so QuillCodeEditor can connect even if the remote process
    // exits slightly before the WS connection is established.
    remoteStdout.listen(
      (chunk) {
        if (bridge._closed) return;
        bridge._buf.addAll(chunk);
        bridge._pump();
      },
      onDone: () {
        bridge._processAlive = false;
        // Close the WebSocket gracefully if already connected.
        bridge._ws?.close();
      },
      onError: (_) {
        bridge._processAlive = false;
        bridge._ws?.close();
      },
    );

    // Accept exactly one WebSocket connection from QuillCodeEditor.
    bridge._serveOne(server, remoteStdin);
    return bridge;
  }

  // ASCII bytes for 'C','o','n','t','e','n','t','-','L','e','n','g','t','h',':'
  static const _clHeader = [67, 111, 110, 116, 101, 110, 116, 45, 76, 101, 110, 103, 116, 104, 58];

  /// Locate the first case-insensitive "Content-Length:" in [_buf] starting
  /// at [from], returning its index or -1.
  int _findContentLength(int from) {
    outer:
    for (int i = from; i <= _buf.length - _clHeader.length; i++) {
      for (int j = 0; j < _clHeader.length; j++) {
        final b = _buf[i + j];
        // Compare case-insensitively (ASCII letters differ by 32)
        if (b != _clHeader[j] && b != _clHeader[j] + 32) continue outer;
      }
      return i;
    }
    return -1;
  }

  /// Parse buffered bytes into LSP frames and forward them as WS messages.
  ///
  /// Robust to leading garbage (e.g. bash login-script stdout output):
  /// scans for the literal "Content-Length:" token rather than assuming it
  /// starts at byte 0, so any non-LSP bytes before the first frame are
  /// safely skipped.
  void _pump() {
    while (true) {
      // 1. Find the start of the next "Content-Length:" token.
      final clStart = _findContentLength(0);
      if (clStart == -1) {
        // No Content-Length token yet.  Drop everything except the last
        // 16 bytes (in case the token is split across chunks).
        if (_buf.length > 16) _buf.removeRange(0, _buf.length - 16);
        return;
      }

      // Discard garbage before the token.
      if (clStart > 0) {
        debugPrint('[LSP bridge] discarding $clStart garbage bytes before Content-Length');
        _buf.removeRange(0, clStart);
      }

      // 2. Find the \r\n\r\n terminator that ends the header block.
      int headerEnd = -1;
      for (int i = 0; i < _buf.length - 3; i++) {
        if (_buf[i] == 0x0D &&
            _buf[i + 1] == 0x0A &&
            _buf[i + 2] == 0x0D &&
            _buf[i + 3] == 0x0A) {
          headerEnd = i;
          break;
        }
      }
      if (headerEnd == -1) return; // header not yet complete — wait

      // 3. Parse Content-Length value from the header section.
      final header = utf8.decode(_buf.sublist(0, headerEnd), allowMalformed: true);
      int? len;
      for (final line in header.split('\r\n')) {
        if (line.toLowerCase().startsWith('content-length:')) {
          len = int.tryParse(line.split(':')[1].trim());
          break;
        }
      }
      if (len == null) {
        // Malformed — skip past this \r\n\r\n and look for the next token.
        _buf.removeRange(0, headerEnd + 4);
        continue;
      }

      // 4. Wait until the full body is buffered.
      if (_buf.length < headerEnd + 4 + len) return;

      final msgBytes = _buf.sublist(headerEnd + 4, headerEnd + 4 + len);
      _buf.removeRange(0, headerEnd + 4 + len);

      // 5. Forward the raw JSON body to the WebSocket client.
      _ws?.add(utf8.decode(msgBytes, allowMalformed: true));
    }
  }

  /// Accept one WebSocket upgrade and bridge WS messages → LSP stdin.
  void _serveOne(HttpServer server, StreamSink<Uint8List> remoteStdin) async {
    try {
      await for (final req in server) {
        if (_closed) break;
        if (!WebSocketTransformer.isUpgradeRequest(req)) {
          req.response.statusCode = 426;
          await req.response.close();
          continue;
        }
        final ws = await WebSocketTransformer.upgrade(req);
        _ws = ws;
        ws.listen(
          (data) {
            if (_closed) return;
            if (!_processAlive) {
              // Remote process died — close WS so LspSocketClient fails fast
              // instead of waiting for the 10-second initialize timeout.
              ws.close();
              return;
            }
            if (data is! String) return;
            // Frame the JSON message with Content-Length header
            final bytes = utf8.encode(data);
            final header = utf8.encode('Content-Length: ${bytes.length}\r\n\r\n');
            remoteStdin.add(Uint8List.fromList([...header, ...bytes]));
          },
          onDone: close,
          onError: (_) => close(),
        );
        break; // Only one client needed
      }
    } catch (_) {}
  }

  /// Close the bridge and release all resources.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _processAlive = false;
    _ws?.close();
    await _server.close(force: true);
  }
}
