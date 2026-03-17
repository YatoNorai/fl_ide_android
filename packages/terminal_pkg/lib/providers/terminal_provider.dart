import 'package:flutter/foundation.dart';

import '../models/terminal_session.dart';

class TerminalProvider extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  int _activeIndex = 0;

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get activeIndex => _activeIndex;
  TerminalSession? get active =>
      _sessions.isEmpty ? null : _sessions[_activeIndex];

  /// Create and start a new terminal session
  Future<TerminalSession> createSession({
    String? label,
    String? executable,
    List<String> arguments = const [],
    Map<String, String>? environment,
    String? workingDirectory,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final session = TerminalSession(
      id: id,
      label: label ?? 'bash ${_sessions.length + 1}',
    );

    session.onExit = (_) => notifyListeners();

    await session.start(
      executable: executable,
      arguments: arguments,
      environment: environment,
      workingDirectory: workingDirectory,
    );

    _sessions.add(session);
    _activeIndex = _sessions.length - 1;
    notifyListeners();
    return session;
  }

  void switchTo(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _activeIndex = index;
    notifyListeners();
  }

  void closeSession(int index) {
    if (index < 0 || index >= _sessions.length) return;
    _sessions[index].kill();
    _sessions.removeAt(index);
    if (_activeIndex >= _sessions.length) {
      _activeIndex = _sessions.isEmpty ? 0 : _sessions.length - 1;
    }
    notifyListeners();
  }

  void closeAll() {
    for (final s in _sessions) {
      s.kill();
    }
    _sessions.clear();
    _activeIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    closeAll();
    super.dispose();
  }
}
