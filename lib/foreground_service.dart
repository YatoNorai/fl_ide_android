import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Entry point for the Android foreground task service.
/// Must be a top-level function annotated with vm:entry-point.
@pragma('vm:entry-point')
void fgServiceCallback() {
  FlutterForegroundTask.setTaskHandler(_IdeTaskHandler());
}

/// Minimal task handler — we only need the service to keep the process alive.
class _IdeTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp) async {}
}
