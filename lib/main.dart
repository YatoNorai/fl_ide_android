import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Foreground service init — keeps FL IDE alive when backgrounded.
  // The service itself is started/stopped by WorkspaceScreen.
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'fl_ide_service',
      channelName: 'FL IDE',
      channelDescription: 'Keeps FL IDE active while developing',
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
