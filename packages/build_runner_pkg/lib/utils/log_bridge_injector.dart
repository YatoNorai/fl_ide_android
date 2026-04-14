import 'dart:io';

import 'package:core/core.dart';
import 'package:project_manager/project_manager.dart';

// ── LogBridgeInjector ─────────────────────────────────────────────────────────
//
// Injects FLIDELogBridge into the user's Android project so that it connects
// back to fl_ide's socket server (port 8877) and forwards the app's own logs
// in real-time — no ADB or READ_LOGS permission required.
//
// Files written (all inside src/debug/ so they're excluded from release builds):
//   <android-root>/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridge.java
//   <android-root>/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridgeInit.java
//   <android-root>/app/src/debug/AndroidManifest.xml   (merged by Gradle)
//
// The ContentProvider trick (same as Firebase/Jetpack Startup) auto-initialises
// the bridge before Application.onCreate() — zero changes to user code.

class LogBridgeInjector {
  /// Finds the Gradle android root for [project].
  ///
  /// Search order:
  ///   1. `<project>/android/`            — Flutter / React Native
  ///   2. `<project>/app/build.gradle`    — Android native (project IS the root)
  ///   3. Shallow scan (depth ≤ 2) for any `app/build.gradle`
  ///   4. Flutter fallback: if `pubspec.yaml` exists, use `<project>/android/`
  ///      even when the directory is absent yet (first run before flutter create
  ///      has finished, or the android/ folder was gitignored).
  ///
  /// Returns the directory path to pass as `<root>` to Gradle, or null if the
  /// project is definitely not Android-based.
  static String? _androidRoot(Project project) {
    final base = project.path;

    // 1. Flutter / React Native — android/ sub-directory
    final flutterAndroid = Directory('$base/android');
    if (flutterAndroid.existsSync()) return flutterAndroid.path;

    // 2. Android native — project root contains app/build.gradle
    if (File('$base/app/build.gradle').existsSync() ||
        File('$base/app/build.gradle.kts').existsSync()) {
      return base;
    }

    // 3. Shallow scan — look for build.gradle up to 2 levels deep.
    //    Handles non-standard layouts (e.g. monorepos).
    try {
      for (final l1 in Directory(base).listSync()) {
        if (l1 is! Directory) continue;
        final candidate = '${l1.path}/app/build.gradle';
        if (File(candidate).existsSync()) return l1.path;
        // depth 2
        try {
          for (final l2 in l1.listSync()) {
            if (l2 is! Directory) continue;
            if (File('${l2.path}/app/build.gradle').existsSync()) return l2.path;
          }
        } catch (_) {}
      }
    } catch (_) {}

    // 4. Flutter fallback: pubspec.yaml present → treat android/ as target
    //    even if it doesn't exist yet (will be created on first build).
    if (File('$base/pubspec.yaml').existsSync()) {
      return '$base/android';
    }

    return null;
  }

  /// Returns true if the bridge files are already present.
  static bool isInjected(Project project) {
    final root = _androidRoot(project);
    if (root == null) return false;
    return File('$root/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridge.java')
        .existsSync();
  }

  /// Writes the three bridge files into the project.
  /// Returns an error string on failure, or null on success.
  static String? inject(Project project) {
    final root = _androidRoot(project);
    if (root == null) {
      return 'Could not find an Android module in ${project.path}.\n'
          'Expected android/app/build.gradle (Flutter/RN) '
          'or app/build.gradle (Android native).';
    }

    try {
      _writeFile('$root/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridge.java',
          _bridgeJava);
      _writeFile('$root/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridgeInit.java',
          _initJava);
      _writeFile('$root/app/src/debug/AndroidManifest.xml', _debugManifest);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  /// Removes the bridge files (and the debug manifest if we created it).
  static void remove(Project project) {
    final root = _androidRoot(project);
    if (root == null) return;
    final files = [
      '$root/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridge.java',
      '$root/app/src/debug/java/com/fl_ide/logbridge/FLIDELogBridgeInit.java',
      '$root/app/src/debug/AndroidManifest.xml',
    ];
    for (final p in files) {
      final f = File(p);
      if (f.existsSync()) f.deleteSync();
    }
    // Clean up empty directories
    final dir = Directory('$root/app/src/debug/java/com/fl_ide/logbridge');
    if (dir.existsSync()) {
      try { dir.deleteSync(recursive: true); } catch (_) {}
    }
  }

  static void _writeFile(String path, String content) {
    final file = File(path);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  // ── Java templates ──────────────────────────────────────────────────────────

  static const int _port = 8877; // must match LogcatProvider.bridgePort

  static final String _bridgeJava = '''
package com.fl_ide.logbridge;

import android.util.Log;
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.InputStreamReader;
import java.io.OutputStreamWriter;
import java.io.PrintWriter;
import java.net.Socket;

/**
 * FL IDE Log Bridge — auto-generated by FL IDE. Do not edit.
 * Remove before publishing: this file is in src/debug/ and is excluded from
 * release builds automatically.
 *
 * Reads the app's own logcat stream and forwards every line to FL IDE
 * over a localhost TCP socket on port $_port.
 * No ADB or READ_LOGS permission is needed.
 */
public class FLIDELogBridge {
    private static final String TAG = "FLIDELogBridge";
    private static volatile Thread sThread;

    public static void start() {
        if (sThread != null && sThread.isAlive()) return;
        sThread = new Thread(FLIDELogBridge::run, "fl-ide-log-bridge");
        sThread.setDaemon(true);
        sThread.start();
    }

    private static void run() {
        // Use fully-qualified android.os.Process to avoid collision with
        // java.lang.Process (the type returned by ProcessBuilder.start()).
        int pid = android.os.Process.myPid();
        while (!Thread.currentThread().isInterrupted()) {
            try {
                // Start logcat filtered to our own process.
                // Declare as java.lang.Process explicitly to avoid ambiguity.
                java.lang.Process logcat = new ProcessBuilder(
                        "logcat", "--pid=" + pid, "-v", "threadtime")
                        .redirectErrorStream(false)
                        .start();

                try (Socket socket = new Socket("127.0.0.1", $_port);
                     PrintWriter out = new PrintWriter(
                             new BufferedWriter(
                                     new OutputStreamWriter(socket.getOutputStream())), true);
                     BufferedReader in = new BufferedReader(
                             new InputStreamReader(logcat.getInputStream()))) {

                    Log.d(TAG, "Connected to FL IDE on port $_port");
                    String line;
                    while ((line = in.readLine()) != null) {
                        out.println(line);
                    }
                } finally {
                    logcat.destroy();
                }
            } catch (Exception e) {
                Log.w(TAG, "FL IDE bridge error: " + e.getMessage());
                // Retry after a short delay (IDE might not be listening yet).
                try { Thread.sleep(2000); } catch (InterruptedException ie) { break; }
            }
        }
    }
}
''';

  static final String _initJava = '''
package com.fl_ide.logbridge;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;

/**
 * FL IDE Log Bridge auto-initializer — auto-generated by FL IDE.
 * Uses the ContentProvider startup pattern (same as Firebase) so that the
 * bridge starts automatically before Application.onCreate() — no code changes
 * needed in your app.
 */
public class FLIDELogBridgeInit extends ContentProvider {
    @Override
    public boolean onCreate() {
        FLIDELogBridge.start();
        return true;
    }

    @Override public Cursor query(Uri u, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues values) { return null; }
    @Override public int delete(Uri uri, String s, String[] a) { return 0; }
    @Override public int update(Uri uri, ContentValues v, String s, String[] a) { return 0; }
}
''';

  static const String _debugManifest = '''<?xml version="1.0" encoding="utf-8"?>
<!-- Auto-generated by FL IDE — do not edit. Remove before publishing. -->
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application>
        <!--
            ContentProvider initializer: starts FLIDELogBridge before
            Application.onCreate() so no code changes are needed in your app.
            This file lives in src/debug/ and is EXCLUDED from release builds.
        -->
        <provider
            android:name="com.fl_ide.logbridge.FLIDELogBridgeInit"
            android:authorities="\${applicationId}.fl_ide_log_bridge"
            android:exported="false"
            android:initOrder="100" />
    </application>
</manifest>
''';
}
