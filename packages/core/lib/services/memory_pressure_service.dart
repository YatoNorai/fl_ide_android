import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Listens for Android memory-pressure events delivered via the
/// [MethodChannel] registered in MainActivity and dispatches them to
/// registered Dart listeners.
///
/// Usage:
/// ```dart
/// MemoryPressureService.instance.addCriticalListener(_onCritical);
/// MemoryPressureService.instance.addModerateListener(_onModerate);
/// // …
/// MemoryPressureService.instance.removeCriticalListener(_onCritical);
/// ```
///
/// Android trim levels used:
///   TRIM_MEMORY_RUNNING_LOW    = 10  → moderate pressure
///   TRIM_MEMORY_MODERATE       = 60  → critical pressure
///   TRIM_MEMORY_COMPLETE       = 80  → critical pressure
class MemoryPressureService {
  static const _channel = MethodChannel('fl_ide/memory');
  static MemoryPressureService? _instance;

  final List<VoidCallback> _onModerate = [];
  final List<VoidCallback> _onCritical = [];

  MemoryPressureService._() {
    _channel.setMethodCallHandler(_handleCall);
  }

  static MemoryPressureService get instance =>
      _instance ??= MemoryPressureService._();

  /// Register a callback invoked when Android signals TRIM_MEMORY_RUNNING_LOW
  /// (level 10–59) — memory is low but the process is not immediately at risk.
  void addModerateListener(VoidCallback cb) => _onModerate.add(cb);

  /// Register a callback invoked when Android signals TRIM_MEMORY_MODERATE or
  /// TRIM_MEMORY_COMPLETE (level >= 60), or fires onLowMemory().
  void addCriticalListener(VoidCallback cb) => _onCritical.add(cb);

  void removeModerateListener(VoidCallback cb) => _onModerate.remove(cb);
  void removeCriticalListener(VoidCallback cb) => _onCritical.remove(cb);

  Future<dynamic> _handleCall(MethodCall call) async {
    switch (call.method) {
      case 'onTrimMemory':
        final level = call.arguments as int;
        if (level >= 60) {
          // TRIM_MEMORY_MODERATE (60) or TRIM_MEMORY_COMPLETE (80)
          _dispatch(_onCritical);
        } else if (level >= 10) {
          // TRIM_MEMORY_RUNNING_LOW (10) or TRIM_MEMORY_RUNNING_CRITICAL (15)
          _dispatch(_onModerate);
        }
        break;
      case 'onLowMemory':
        _dispatch(_onCritical);
        break;
    }
  }

  /// Dispatches to a snapshot of [listeners] so that callbacks may safely
  /// add/remove entries during iteration.
  void _dispatch(List<VoidCallback> listeners) {
    for (final cb in List.of(listeners)) {
      cb();
    }
  }
}
