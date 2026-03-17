import 'package:animated_text_kit/animated_text_kit.dart';
import 'package:flutter/material.dart';

/// Terminal-style splash screen with animated typing text.
/// Calls [onFinished] when the animation completes.
class SplashScreen extends StatelessWidget {
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.8,
          child: AnimatedTextKit(
            animatedTexts: [
              TyperAnimatedText(
                'Initializing FL IDE...',
                textStyle: const TextStyle(
                  fontSize: 24.0,
                  color: Colors.lightGreenAccent,
                  fontFamily: 'monospace',
                ),
                speed: const Duration(milliseconds: 80),
              ),
              TyperAnimatedText(
                'Loading modules...',
                textStyle: const TextStyle(
                  fontSize: 24.0,
                  color: Colors.lightBlueAccent,
                  fontFamily: 'monospace',
                ),
                speed: const Duration(milliseconds: 80),
              ),
              TyperAnimatedText(
                'Preparing workspace...',
                textStyle: const TextStyle(
                  fontSize: 24.0,
                  color: Colors.pinkAccent,
                  fontFamily: 'monospace',
                ),
                speed: const Duration(milliseconds: 80),
              ),
            ],
            totalRepeatCount: 1,
            onFinished: onFinished,
          ),
        ),
      ),
    );
  }
}
