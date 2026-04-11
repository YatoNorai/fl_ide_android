import 'dart:async';

/// Common interface for DAP clients (stdio or TCP).
abstract class DapClientBase {
  Stream<Map<String, dynamic>> get events;
  bool get isRunning;

  Future<Map<String, dynamic>> sendRequest(
    String command, [
    Map<String, dynamic>? arguments,
  ]);

  Future<void> dispose();
}
