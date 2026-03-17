import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedToggle extends StatefulWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  final Color? iconColor;
  final Color? toggleBgColor;
  final Color? inactiveKnobColor;
  final Color? activeKnobColor;

  const AnimatedToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.iconColor,
    this.toggleBgColor,
    this.inactiveKnobColor,
    this.activeKnobColor,
  });

  @override
  State<AnimatedToggle> createState() => _AnimatedToggleState();
}

class _AnimatedToggleState extends State<AnimatedToggle>
    with TickerProviderStateMixin {
  late AnimationController _knobController;
  late AnimationController _shapesController;

  late Animation<double> _knobPositionAnimation;
  late Animation<double> _knobInitialScaleAnimation;
  late Animation<double> _knobCheckedScaleAnimation;

  late Animation<double> _xShapeScaleAnimation;
  late Animation<double> _vShapeScaleAnimation;

  double _knobSize = 0.0;
  double _knobPadding = 0.0;
  double _toggleWidth = 0.0;
  double _toggleHeight = 0.0;

  @override
  void initState() {
    super.initState();

    _knobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _shapesController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    const Cubic shapesCurve = Cubic(1.0, 0.0, 0.0, 1.0);

    _xShapeScaleAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _shapesController,
        curve: const Interval(0.5, 1.0, curve: shapesCurve),
      ),
    );

    _vShapeScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _shapesController,
        curve: const Interval(0.5, 1.0, curve: shapesCurve),
      ),
    );

    if (widget.value) {
      _knobController.value = 1.0;
      _shapesController.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant AnimatedToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      if (widget.value) {
        _knobController.forward();
        _shapesController.forward();
      } else {
        _knobController.reverse();
        _shapesController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _knobController.dispose();
    _shapesController.dispose();
    super.dispose();
  }

  void _initializeSizeDependentAnimations() {
    final double endPosition = _toggleWidth - _knobSize - _knobPadding;

    _knobPositionAnimation =
        Tween<double>(begin: _knobPadding, end: endPosition).animate(
      CurvedAnimation(parent: _knobController, curve: Curves.easeOut),
    );

    _knobInitialScaleAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _knobController, curve: Curves.easeOut),
    );
    _knobCheckedScaleAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _knobController, curve: Curves.easeOut),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color effectiveIconColor = widget.iconColor ?? colorScheme.onPrimary;
    final Color effectiveToggleBgColor =
        widget.toggleBgColor ?? colorScheme.surfaceContainerHighest;
    final Color effectiveActiveKnobColor =
        widget.activeKnobColor ?? colorScheme.secondary;

    return LayoutBuilder(
      builder: (context, constraints) {
        _toggleWidth = constraints.maxWidth;
        _toggleHeight = constraints.maxHeight;

        _knobSize = _toggleHeight * 0.75;
        _knobPadding = (_toggleHeight - _knobSize) / 3.5;

        _initializeSizeDependentAnimations();

        return GestureDetector(
          onTap: () => widget.onChanged(!widget.value),
          child: Container(
            width: _toggleWidth,
            height: _toggleHeight,
            decoration: BoxDecoration(
              color: effectiveToggleBgColor,
              border: Border.all(color: colorScheme.secondary, width: 2),
              borderRadius: BorderRadius.circular(_toggleHeight / 2),
            ),
            child: Stack(
              children: [
                // Inactive knob (X shape)
                AnimatedBuilder(
                  animation: _knobController,
                  builder: (context, child) {
                    return Positioned(
                      left: _knobPositionAnimation.value,
                      bottom: _knobPadding,
                      child: Transform.scale(
                        scale: _knobInitialScaleAnimation.value,
                        child: Container(
                          width: _knobSize,
                          height: _knobSize,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                          ),
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _shapesController,
                              builder: (context, child) {
                                return CustomPaint(
                                  size: Size(_knobSize, _knobSize),
                                  painter: XShapePainter(
                                    scale: _xShapeScaleAnimation.value,
                                    iconColor: effectiveIconColor,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),

                // Active knob (checkmark shape)
                AnimatedBuilder(
                  animation: _knobController,
                  builder: (context, child) {
                    return Positioned(
                      left: _knobPositionAnimation.value - 4,
                      bottom: _knobPadding,
                      child: Transform.scale(
                        scale: _knobCheckedScaleAnimation.value,
                        child: Container(
                          width: _knobSize,
                          height: _knobSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: effectiveActiveKnobColor,
                          ),
                          child: Center(
                            child: AnimatedBuilder(
                              animation: _shapesController,
                              builder: (context, child) {
                                return CustomPaint(
                                  size: Size(_knobSize, _knobSize),
                                  painter: VShapePainter(
                                    scale: _vShapeScaleAnimation.value,
                                    iconColor: effectiveIconColor,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
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

  XShapePainter({required this.scale, required this.iconColor, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.fill;

    final double borderRadius = size.width * 0.0625;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);

    final double barWidth = size.width * 0.125;
    final double barHeight = size.width * 0.75;

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
  bool shouldRepaint(covariant XShapePainter oldDelegate) =>
      oldDelegate.scale != scale || oldDelegate.iconColor != iconColor;
}

class VShapePainter extends CustomPainter {
  final double scale;
  final Color iconColor;

  VShapePainter({required this.scale, required this.iconColor, super.repaint});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.125
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-size.width / 2, -size.height / 2);

    final Path checkPath = Path();
    checkPath.moveTo(size.width * 0.25, size.height * 0.5);
    checkPath.lineTo(size.width * 0.45, size.height * 0.7);
    checkPath.lineTo(size.width * 0.75, size.height * 0.3);

    canvas.drawPath(checkPath, paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VShapePainter oldDelegate) =>
      oldDelegate.scale != scale || oldDelegate.iconColor != iconColor;
}
