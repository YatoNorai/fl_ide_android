import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Transparent system bars (same as termare)
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Full screen immersive
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(const FlIdeApp());
}
