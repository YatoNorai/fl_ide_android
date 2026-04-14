import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

/// Lottie-based morphing devices splash screen.
///
/// Plays the animation once, then navigates to [nextPage] with a
/// fade+slide transition.
class MorphingDevicesSplash extends StatefulWidget {
  const MorphingDevicesSplash({
    super.key,
    required this.nextPage,
    this.assetPath = 'assets/animations/device_morphing_exact.json',
    this.backgroundLightColor = Colors.white,
    this.backgroundDarkColor = const Color(0xFF0B0B0B),
    this.animationLightColor = Colors.black,
    this.animationDarkColor = Colors.white,
    this.splashDuration = const Duration(milliseconds: 5433),
    this.fadeDuration = const Duration(milliseconds: 450),
    this.slideOffset = const Offset(0, 0.02),
    this.fit = BoxFit.contain,
    this.useThemePrimaryColor = false,
    this.onCompleted,
  });

  final Widget nextPage;
  final String assetPath;
  final Color backgroundLightColor;
  final Color backgroundDarkColor;
  final Color animationLightColor;
  final Color animationDarkColor;
  final Duration splashDuration;
  final Duration fadeDuration;
  final Offset slideOffset;
  final BoxFit fit;
  final bool useThemePrimaryColor;
  final VoidCallback? onCompleted;

  @override
  State<MorphingDevicesSplash> createState() => _MorphingDevicesSplashState();
}

class _MorphingDevicesSplashState extends State<MorphingDevicesSplash>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.splashDuration,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) _goNext();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _controller.forward();
    });
  }

  @override
  void didUpdateWidget(covariant MorphingDevicesSplash oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.splashDuration != widget.splashDuration) {
      _controller.duration = widget.splashDuration;
    }
  }

  void _goNext() {
    if (!mounted || _navigated) return;
    _navigated = true;
    widget.onCompleted?.call();
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, animation, __) => widget.nextPage,
        transitionDuration: widget.fadeDuration,
        reverseTransitionDuration: const Duration(milliseconds: 250),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: widget.slideOffset,
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? widget.backgroundDarkColor : widget.backgroundLightColor;
    final animColor = widget.useThemePrimaryColor
        ? Theme.of(context).colorScheme.primary
        : (isDark ? widget.animationDarkColor : widget.animationLightColor);

    return Scaffold(
      backgroundColor: bgColor,
      body: SizedBox.expand(
        child: Center(
          child: Lottie.asset(
            widget.assetPath,
            controller: _controller,
            repeat: false,
            animate: false,
            fit: widget.fit,
            width: 800,
            height: 800,
            addRepaintBoundary: true,
            frameRate: FrameRate.composition,
            filterQuality: FilterQuality.high,
            delegates: LottieDelegates(
              values: [
                ValueDelegate.colorFilter(
                  const ['**'],
                  value: ColorFilter.mode(animColor, BlendMode.srcIn),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
