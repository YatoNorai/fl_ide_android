import 'dart:async';
import 'dart:io';

import 'package:core/core.dart' show RuntimeEnvir;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'providers/settings_provider.dart';

/// Holds results computed during the pre-launch phase (before runApp).
/// All fields are immutable after [AppBootData.initialize] completes.
abstract final class AppBootData {
  static bool gitAvailable = false;
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run all pre-launch work in parallel so the UI never has to wait for
  // individual async results — git check, settings warm-up, and asset
  // pre-caching all finish before the first frame is drawn.
  final results = await Future.wait([
    SettingsProvider.warmUp(),
   // _checkGit(),
    _precacheAssets(),
  ]);
 // AppBootData.gitAvailable = results[1] as bool;

  // Foreground service init — keeps FL IDE alive when backgrounded.
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.skipServiceResponseCheck = true;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'layer_service',
      channelName: 'FL IDE Background',
      channelDescription: 'Keeps FL IDE active while developing',
      channelImportance: NotificationChannelImportance.HIGH,
      priority: NotificationPriority.HIGH,
      onlyAlertOnce: true,
      enableVibration: false,
      playSound: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const FlIdeApp());
}

/// Checks whether git is available in the Termux environment.
Future<bool> _checkGit() async {
  try {
    final r = await Process.run(
      'git', ['--version'],
      environment: RuntimeEnvir.baseEnv,
    ).timeout(const Duration(seconds: 5));
    return r.exitCode == 0;
  } catch (_) {
    return false;
  }
}

/// Pre-warms Flutter's image cache for every bundled asset that the home
/// screen shows, so there is zero decode stutter on first render.
Future<void> _precacheAssets() async {
  await _resolveAsset('assets/logo.png');
}

Future<void> _resolveAsset(String assetPath) async {
  final completer = Completer<void>();
  late final ImageStreamListener listener;
  final stream = AssetImage(assetPath).resolve(ImageConfiguration.empty);
  listener = ImageStreamListener(
    (_, __) { stream.removeListener(listener); completer.complete(); },
    onError: (_, __) { stream.removeListener(listener); completer.complete(); },
  );
  stream.addListener(listener);
  await completer.future.timeout(
    const Duration(seconds: 3),
    onTimeout: () {},
  );
}
