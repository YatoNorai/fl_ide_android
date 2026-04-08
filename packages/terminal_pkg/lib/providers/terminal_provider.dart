import 'package:flutter/foundation.dart';

import '../models/terminal_session.dart';

class TerminalProvider extends ChangeNotifier {
  final List<TerminalSession> _sessions = [];
  int _activeIndex = 0;
  // Sessions pinned to the top tab bar
  final Set<String> _topBarIds = {};
  // Which top-bar terminal is currently shown in the main area (null = file editor)
  String? _topBarActiveId;

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  int get activeIndex => _activeIndex;
  TerminalSession? get active =>
      _sessions.isEmpty ? null : _sessions[_activeIndex];

  /// Sessions visible in the bottom-sheet terminal tab.
  List<TerminalSession> get sheetSessions =>
      _sessions.where((s) => !_topBarIds.contains(s.id)).toList();

  /// Sessions pinned to the top tab bar.
  List<TerminalSession> get topBarSessions =>
      _sessions.where((s) => _topBarIds.contains(s.id)).toList();

  /// ID of the top-bar terminal currently shown in the main area.
  String? get topBarActiveId => _topBarActiveId;

  /// True when a top-bar terminal (not the file editor) should be shown.
  bool get isTopBarTerminalActive =>
      _topBarActiveId != null && _topBarIds.contains(_topBarActiveId!);

  TerminalSession? get topBarActiveSession => _topBarActiveId == null
      ? null
      : _sessions.where((s) => s.id == _topBarActiveId).firstOrNull;

  /// Pin a session to the top tab bar.
  void pinToTopBar(String sessionId) {
    _topBarIds.add(sessionId);
    _topBarActiveId = sessionId;
    notifyListeners();
  }

  /// Move a session back to the bottom-sheet terminal tab.
  void unpinFromTopBar(String sessionId) {
    _topBarIds.remove(sessionId);
    if (_topBarActiveId == sessionId) {
      _topBarActiveId =
          _topBarIds.isEmpty ? null : _topBarIds.last;
    }
    notifyListeners();
  }

  /// Activate a top-bar terminal in the main content area.
  void setTopBarActive(String sessionId) {
    if (_topBarIds.contains(sessionId)) {
      _topBarActiveId = sessionId;
      notifyListeners();
    }
  }

  /// Deactivate the top-bar terminal (switch back to file editor view).
  void clearTopBarActive() {
    if (_topBarActiveId != null) {
      _topBarActiveId = null;
      notifyListeners();
    }
  }

  /// Create and start a new terminal session.
  ///
  /// If [sshSetup] is provided it is called instead of [TerminalSession.start],
  /// allowing an SSH shell to be attached via [TerminalSession.attachRemote].
  Future<TerminalSession> createSession({
    String? label,
    String? executable,
    List<String> arguments = const [],
    Map<String, String>? environment,
    String? workingDirectory,
    // Optional SSH setup: called instead of session.start() for SSH-backed sessions
    Future<void> Function(TerminalSession session)? sshSetup,
  }) async {
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final session = TerminalSession(
      id: id,
      label: label ?? 'bash ${_sessions.length + 1}',
    );

    session.onExit = (_) => notifyListeners();

    if (sshSetup != null) {
      await sshSetup(session);
    } else {
      await session.start(
        executable: executable,
        arguments: arguments,
        environment: environment,
        workingDirectory: workingDirectory,
      );
    }

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
    final id = _sessions[index].id;
    _sessions[index].kill();
    _sessions.removeAt(index);
    _topBarIds.remove(id);
    if (_topBarActiveId == id) {
      _topBarActiveId =
          _topBarIds.isEmpty ? null : _topBarIds.last;
    }
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
    _topBarIds.clear();
    _topBarActiveId = null;
    _activeIndex = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    closeAll();
    super.dispose();
  }
}
