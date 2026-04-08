// core/lib/utils/show_themed_dialog.dart
//
// App-wide helper that wraps showDialog so that the system navigation bar
// becomes transparent + blurred whenever a dialog is open.
//
// The key detail: AnnotatedRegion with sized:false covers the ENTIRE screen,
// not just the dialog widget bounds. Without this, the annotation only covers
// the AlertDialog area and the nav bar keeps the app-level surface color.

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<T?> showThemedDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  String? barrierLabel,
  Color barrierColor = Colors.black54,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final iconBrightness = isDark ? Brightness.light : Brightness.dark;

  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: barrierLabel,
    // Use transparent barrier — we render our own full-screen scrim with blur
    // so it naturally extends into the nav bar area.
    barrierColor: Colors.transparent,
    builder: (ctx) => AnnotatedRegion<SystemUiOverlayStyle>(
      // sized: false → annotation covers the whole screen, not just the dialog
      // widget bounds, so it overrides the app-level nav bar color.
      sized: false,
      value: SystemUiOverlayStyle(
        // Navigation bar
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: iconBrightness,
        systemNavigationBarDividerColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
        // Status bar — also transparent + blurred by the BackdropFilter below
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: iconBrightness,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: RepaintBoundary(
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12,), /* Stack(
          children: [
            // Full-screen blur + scrim that extends behind the nav bar.
            Positioned.fill(
              child: RepaintBoundary(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                  child: ColoredBox(color: barrierColor),
                ),
              ),
            ),
            // The actual dialog content (AlertDialog etc. centers itself).
            builder(ctx),
          ],
        ), */
        child:  builder(ctx),
            ),
      ),),
  );
}
