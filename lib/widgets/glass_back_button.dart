// lib/widgets/glass_back_button.dart
//
// A back-button (or any icon button) that wraps itself in an OCLiquidGlass
// pill when the "Liquid Glass" theme is active, or falls back to a plain
// IconButton otherwise.

import 'package:flutter/material.dart';
import 'package:oc_liquid_glass/oc_liquid_glass.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

const _kGlassSettings = OCLiquidGlassSettings(
  blurRadiusPx: 3.0,
  refractStrength: -0.06,
  distortFalloffPx: 18.0,
  specStrength: 0.28,
  specPower: 6.0,
  specWidth: 0.35,
  lightbandStrength: 0.18,
  lightbandWidthPx: 5.0,
);

class GlassBackButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final Color? iconColor;

  const GlassBackButton({
    super.key,
    this.icon = Icons.arrow_back_ios_new_rounded,
    this.onPressed,
    this.tooltip,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final liquidGlass = context.watch<SettingsProvider>().liquidGlass;
    final btn = IconButton(
      icon: Icon(icon, color: iconColor ?? cs.onSurface, size: 22),
      onPressed: onPressed ?? () => Navigator.maybePop(context),
      tooltip: tooltip ?? MaterialLocalizations.of(context).backButtonTooltip,
    );
    if (!liquidGlass) return btn;
    return OCLiquidGlassGroup(
      settings: _kGlassSettings,
      child: OCLiquidGlass(
        width: 42,
        height: 42,
        borderRadius: 21,
        color: cs.surface.withValues(alpha: 0.08),
        child: btn,
      ),
    );
  }
}
