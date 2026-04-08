import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

class AnimatedToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  final Color? iconColor;
  final Color? toggleBgColor;
  final Color? inactiveKnobColor;
  final Color? activeKnobColor;
  final Color? inactiveBorderColor;
  final Color? activeBorderColor;

  const AnimatedToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.iconColor,
    this.toggleBgColor,
    this.inactiveKnobColor,
    this.activeKnobColor,
    this.inactiveBorderColor,
    this.activeBorderColor,
  });

  @override
  State<AnimatedToggle> createState() => _AnimatedToggleState();
}

class _AnimatedToggleState extends State<AnimatedToggle>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 600);
  static const Cubic _shapeCurve = Cubic(1.0, 0.0, 0.0, 1.0);

  static const double _knobOffsetX = -2.0;
  static const double _knobOffsetY = 2.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.value ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant AnimatedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _intervalTransform(
    double t,
    double begin,
    double end, {
    Curve curve = Curves.linear,
  }) {
    if (t <= begin) return 0.0;
    if (t >= end) return 1.0;
    final double normalized = (t - begin) / (end - begin);
    return curve.transform(normalized);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color effectiveIconColor = widget.iconColor ?? colorScheme.onPrimary;

    final Color effectiveInactiveKnobColor =
        widget.inactiveKnobColor ?? colorScheme.error;

    final Color effectiveActiveKnobColor =
        widget.activeKnobColor ?? colorScheme.secondary;

    final Color effectiveInactiveBorderColor =
        widget.inactiveBorderColor ?? colorScheme.error;

    final Color effectiveActiveBorderColor =
        widget.activeBorderColor ?? colorScheme.secondary;

    final Color effectiveToggleBgColor =
        widget.toggleBgColor ?? colorScheme.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double width =
            constraints.hasBoundedWidth ? constraints.maxWidth : 72.0;
        final double height =
            constraints.hasBoundedHeight ? constraints.maxHeight : 40.0;

        final double knobSize = height * 0.75;
        final double knobPadding = (height - knobSize) / 2;

        final double knobStart = knobPadding;
        final double knobEnd = width - knobSize - knobPadding;

        return Semantics(
          button: true,
          toggled: widget.value,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => widget.onChanged(!widget.value),
              borderRadius: BorderRadius.circular(height / 2),
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: effectiveToggleBgColor,
                  border: Border.all(
                    color: widget.value
                        ? effectiveActiveBorderColor
                        : effectiveInactiveBorderColor,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(height / 2),
                ),
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    final double t = _controller.value;

                    final double knobT = _intervalTransform(
                      t,
                      0.0,
                      0.5,
                      curve: Curves.easeOut,
                    );

                    final double shapeT = _intervalTransform(
                      t,
                      0.5,
                      1.0,
                      curve: _shapeCurve,
                    );

                    final double left =
                        lerpDouble(knobStart, knobEnd, knobT) ?? knobStart;

                    final double knobLeft = left + _knobOffsetX;
                    final double knobBottom =
                        math.max(0.0, knobPadding - _knobOffsetY);

                    final double inactiveScale =
                        (1.0 - knobT).clamp(0.0, 1.0);
                    final double activeScale = knobT.clamp(0.0, 1.0);
                    final double xShapeScale = (1.0 - shapeT).clamp(0.0, 1.0);
                    final double vShapeScale = shapeT.clamp(0.0, 1.0);

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned(
                          left: knobLeft,
                          bottom: knobBottom,
                          child: Transform.scale(
                            scale: inactiveScale,
                            child: RepaintBoundary(
                              child: Container(
                                width: knobSize,
                                height: knobSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: effectiveInactiveKnobColor,
                                ),
                                child: Center(
                                  child: CustomPaint(
                                    size: Size(knobSize, knobSize),
                                    painter: XShapePainter(
                                      scale: xShapeScale,
                                      iconColor: effectiveIconColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          left: knobLeft,
                          bottom: knobBottom,
                          child: Transform.scale(
                            scale: activeScale,
                            child: RepaintBoundary(
                              child: Container(
                                width: knobSize,
                                height: knobSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: effectiveActiveKnobColor,
                                ),
                                child: Center(
                                  child: CustomPaint(
                                    size: Size(knobSize, knobSize),
                                    painter: VShapePainter(
                                      scale: vShapeScale,
                                      iconColor: effectiveIconColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class XShapePainter extends CustomPainter {
  final double scale;
  final Color iconColor;

  XShapePainter({
    required this.scale,
    required this.iconColor,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final double borderRadius = size.width * 0.0625;
    final double barWidth = size.width * 0.125;
    final double barHeight = size.width * 0.75;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-45 * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-barWidth / 2, -barHeight / 2, barWidth, barHeight),
        Radius.circular(borderRadius),
      ),
      paint,
    );
    canvas.restore();

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(45 * math.pi / 180);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-barWidth / 2, -barHeight / 2, barWidth, barHeight),
        Radius.circular(borderRadius),
      ),
      paint,
    );
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant XShapePainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.iconColor != iconColor;
  }
}

class VShapePainter extends CustomPainter {
  final double scale;
  final Color iconColor;

  VShapePainter({
    required this.scale,
    required this.iconColor,
    super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.125
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);

    final Path checkPath = Path()
      ..moveTo(size.width * 0.25, size.height * 0.5)
      ..lineTo(size.width * 0.45, size.height * 0.7)
      ..lineTo(size.width * 0.75, size.height * 0.3);

    canvas.drawPath(checkPath, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VShapePainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.iconColor != iconColor;
  }
}