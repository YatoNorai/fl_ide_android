import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';
import 'providers/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-warm SharedPreferences so SettingsProvider loads synchronously on first
  // build, eliminating the theme-color flash on HomeScreen.
  await SettingsProvider.warmUp();

  // Foreground service init — keeps FL IDE alive when backgrounded.
  // The service itself is started/stopped by WorkspaceScreen.
  FlutterForegroundTask.initCommunicationPort();
  // Skip the 5-second binding check — on some Android devices the service
  // takes longer to bind and throws ServiceTimeoutException. The service still
  // starts; we just don't wait for confirmation.
  FlutterForegroundTask.skipServiceResponseCheck = true;
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'layer_service',
      channelName: 'L A Y E R',
      channelDescription: 'Keeps L A Y E R active while developing',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
      onlyAlertOnce: true,
      enableVibration: false,
      playSound: false,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,   // keep CPU alive → SSH keepalive fires every 25s
      allowWifiLock: true,   // keep WiFi radio awake → no TCP drop on screen off
    ),
  );

  // Transparent system bars (same as termare)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Full screen immersive
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Lock all screens to portrait by default
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  runApp(const FlIdeApp());
}
