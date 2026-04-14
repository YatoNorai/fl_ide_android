import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app.dart' show showThemedDialog;
import '../l10n/app_strings.dart';
import 'animated_toggle.dart';

class SettingsPageScaffold extends StatefulWidget {
  final String title;
  final Widget child;
  final VoidCallback onBackPressed;
  final bool canPop;
  final VoidCallback? onSystemBack;
  final ScrollController? controller;

  const SettingsPageScaffold({
    super.key,
    required this.title,
    required this.child,
    required this.onBackPressed,
    this.canPop = false,
    this.onSystemBack,
    this.controller,
  });

  @override
  State<SettingsPageScaffold> createState() => _SettingsPageScaffoldState();
}

class _SettingsPageScaffoldState extends State<SettingsPageScaffold> {
  static const double _maxExtent = 180.0;
  static const double _minExtent = kToolbarHeight;
  static const double _expandedLeft = 20.0;
  static const double _collapsedLeft = 120.0;
  static const double _expandedBottom = 0.0;
  static const double _collapsedBottom = 8.0;

  late final ScrollController _internalController;
  ScrollController get _scrollController => widget.controller ?? _internalController;

  double get _collapseRange => _maxExtent - _minExtent;

  ScrollDirection? _lastDirection;
  bool _snapQueued = false;
  bool _isSnapping = false;

  @override
  void initState() {
    super.initState();
    _internalController = ScrollController();
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _internalController.dispose();
    }
    super.dispose();
  }

  void _queueSnap() {
    if (_snapQueued) return;
    _snapQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapQueued = false;
      _snapHeader();
    });
  }

  Future<void> _snapHeader() async {
    if (!mounted || _isSnapping || !_scrollController.hasClients) return;

    final position = _scrollController.position;
    final offset = position.pixels.clamp(0.0, _collapseRange);
    if (offset <= 0.0 || offset >= _collapseRange) return;

    final target = switch (_lastDirection) {
      ScrollDirection.forward => _collapseRange,
      ScrollDirection.reverse => 0.0,
      _ => offset < (_collapseRange / 2) ? 0.0 : _collapseRange,
    };

    if ((target - offset).abs() < 0.5) return;

    _isSnapping = true;
    try {
      await _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } catch (_) {
      // Ignore if the scroll position is no longer attached.
    } finally {
      _isSnapping = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
 final card = Theme.of(context).cardTheme;
    return PopScope(
      canPop: widget.canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.onSystemBack != null) widget.onSystemBack!.call();
      },
      child: Scaffold(
       // backgroundColor: colors.surface,
        body: NotificationListener<UserScrollNotification>(
          onNotification: (notification) {
            if (notification.metrics.axis == Axis.vertical) {
              _lastDirection = notification.direction;
              if (notification.direction == ScrollDirection.idle) {
                _queueSnap();
              }
            }
            return false;
          },
          child: NotificationListener<ScrollEndNotification>(
            onNotification: (notification) {
              _queueSnap();
              return false;
            },
            child: CustomScrollView(
            controller: _scrollController,
            slivers: [
              SliverAppBar(
                expandedHeight: _maxExtent,
                floating: false,
                snap: false,
                pinned: true,
               // backgroundColor: colors.surface,
                leadingWidth: 65,
                leading: Padding(
                  padding: const EdgeInsets.only(left: 20),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded,),
                    style: IconButton.styleFrom(
                      backgroundColor: colors.surfaceContainerHighest .withValues(alpha: 0.7),
                    //  foregroundColor: card.color?.withValues(alpha: 0.7),
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(5),
                    ),
                    onPressed: widget.onBackPressed,
                  ),
                ),
                flexibleSpace: LayoutBuilder(
                  builder: (context, constraints) {
                    final double currentHeight = constraints.biggest.height;
                    double t = (currentHeight - _minExtent) / (_maxExtent - _minExtent);
                    t = t.clamp(0.0, 1.0);
                    final double left = _expandedLeft + (_collapsedLeft - _expandedLeft) * (1 - t);
                    final double bottom = _expandedBottom + (_collapsedBottom - _expandedBottom) * (1 - t);
                    final double fontSize = 30 - (30 - 18) * (1 - t);
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                      //   DecoratedBox(decoration: BoxDecoration(color: colors.surfaceContainer)),
                        Positioned(
                          left: left,
                          bottom: bottom,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 16, bottom: 8),
                            child: Text(
                              widget.title,
                              style: TextStyle(
                                fontSize: fontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverToBoxAdapter(child: widget.child),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget settingsSectionHeader(BuildContext context,String title) {
   final color = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
    child: Text(
      title,
      style:  TextStyle(
       // fontSize: 15,
       // fontWeight: FontWeight.w500,
        color: color.primary,
      ),
    ),
  );
}

Widget settingsOptionTile(
  BuildContext context, {
  required String title,
  String? subtitle,
  required VoidCallback onTap,
  required Color iconBg,
  required IconData icon,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
}) {
  final colors = Theme.of(context).colorScheme;
   final card = Theme.of(context).cardTheme;
  return Card(
   // elevation: 0,
   // color: card.color?.withValues(alpha: 0.4),
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 1),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
      title: Text(title),
      subtitle: subtitle != null
          ? Text(subtitle, maxLines: 1)
          : null,
      onTap: onTap,
    ),
  );
}

Widget settingsInfoTile(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Color iconBg,
  required IconData icon,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
}) {
  final colors = Theme.of(context).colorScheme;
  final card = Theme.of(context).cardTheme;
  return Card(
  /*   elevation: 0, */
   /*  color: card.color?.withOpacity(0.5), */
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 1),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
      title: Text(title, ),
      subtitle: Text(subtitle, maxLines: 2),
    ),
  );
}

Widget settingsSwitchTile(
  BuildContext context, {
  required String title,
  required String subtitle,
  required bool value,
  required ValueChanged<bool> onChanged,
  required Color iconBg,
  required IconData icon,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
  bool enabled = true,
  String? infoText,
}) {
  final colors = Theme.of(context).colorScheme;
   final cardColor = Theme.of(context).cardTheme;
  final card = Opacity(
    opacity: enabled ? 1.0 : 0.4,
    child: Card(
   //   elevation: 0,
    //  color:cardColor.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: AbsorbPointer(
        absorbing: !enabled,
        child: ListTile(
          minTileHeight: 50,
          leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
          title: Text(title),
          subtitle: Text(subtitle,),
          trailing: SizedBox(
            width: 51,
            height: 30,
            child: AnimatedToggle(value: value, onChanged: onChanged),
          ),
          onTap: () => onChanged(!value),
        ),
      ),
    ),
  );
  if (infoText == null) return card;
  return Stack(
    children: [
      card,
      Positioned(top: 4, right: 4, child: settingsInfoButton(context, title, infoText)),
    ],
  );
}

Widget settingsInfoButton(BuildContext context, String title, String body) {
  final cs = Theme.of(context).colorScheme;
  return Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: () => settingsShowInfoDialog(context, title, body),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.info_outline, size: 14, color: cs.onSurfaceVariant.withValues(alpha: 0.28)),
      ),
    ),
  );
}

Route<T> settingsFadeRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 220),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
          reverseCurve: Curves.easeIn,
        ),
        child: child,
      );
    },
  );
}

void settingsShowInfoDialog(BuildContext context, String title, String body) {
  final s = AppStrings.of(context);
  showThemedDialog<void>(
    context: context,
    title: s.settingInfoTitle,
    builder: (ctx) =>  Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style:  GoogleFonts.openSans(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 10),
            Text(body, style:  GoogleFonts.openSans(height: 1.5)),
          ],
        ),
    ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(s.close)),
      ],
    
  );
}

Widget settingsPickerTile(
  BuildContext context, {
  required String title,
  String? subtitle,
  required String value,
  required List<String> options,
  required ValueChanged<String> onChanged,
  required Color iconBg,
  required IconData icon,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
  String? infoText,
}) {
  final colors = Theme.of(context).colorScheme;
    final cardColor = Theme.of(context).cardTheme;
  final card = Card(
   // elevation: 0,
  // color: cardColor.color?.withOpacity(0.5),
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
      title: Text(title),
      subtitle: Text(value),
     // trailing: const Icon(Icons.chevron_right),
      onTap: () => settingsShowPickerDialog(context, title, value, options, onChanged),
    ),
  );
  if (infoText == null) return card;
  return Stack(
    children: [
      card,
      Positioned(top: 4, right: 4, child: settingsInfoButton(context, title, infoText)),
    ],
  );
}

void settingsShowPickerDialog(
  BuildContext context,
  String title,
  String current,
  List<String> options,
  ValueChanged<String> onChanged,
) {
  showThemedDialog<void>(
    context: context,
    title: title,
    builder: (ctx) {
      return  Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((o) {
            return RadioListTile<String>(
              value: o,
              groupValue: current,
              title: Text(o),
              onChanged: (v) {
                if (v != null) {
                  onChanged(v);
                  Navigator.pop(ctx);
                }
              },
            );
          }).toList(),
        
      );
    },
  );
}

Widget settingsSliderTile(
  BuildContext context, {
  required String title,
  required double value,
  required double min,
  required double max,
  required String valueLabel,
  required ValueChanged<double> onChanged,
  required Color iconBg,
  required IconData icon,
  int? divisions,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
  String? infoText,
}) {
  final colors = Theme.of(context).colorScheme;
    final cardColor = Theme.of(context).cardTheme;
  final card = Card(
   // elevation: 0,
  //  color: cardColor.color?.withOpacity(0.5),
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 1),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 5, 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title),
                    ),
                    Container(
                      margin: const EdgeInsets.only(right: 25),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(valueLabel,
                          style: GoogleFonts.openSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                              /* fontFamily: 'monospace' */)),
                    ),
                  ],
                ),
               // const SizedBox(height: 4),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(year2023: false),
                  child: Slider(
                    year2023: false,
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    onChanged: onChanged,
                    divisions: divisions,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  if (infoText == null) return card;
  return Stack(
    children: [
      card,
      Positioned(top: 4, right: 4, child: settingsInfoButton(context, title, infoText)),
    ],
  );
}

Widget settingsPathInputTile(
  BuildContext context, {
  required String label,
  required Color iconBg,
  required IconData icon,
  required String value,
  required String hint,
  required VoidCallback onTap,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
}) {
  final colors = Theme.of(context).colorScheme;
  final card = Theme.of(context).cardTheme;
  return Card(
    elevation: 0,
    color: card.color?.withOpacity(0.5),
    shape: RoundedRectangleBorder(borderRadius: borderRadius),
    margin: const EdgeInsets.symmetric(vertical: 2),
    child: ListTile(
      leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
      title: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(label, style: TextStyle(color: colors.onSurface)),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(
          value.isEmpty ? 'Default (auto-detect)' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style:  GoogleFonts.openSans(fontSize: 14, )
        ),
      ),
     // trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

Widget settingsAboutCard(
  BuildContext context, {
  required Widget child,
  BorderRadiusGeometry borderRadius = BorderRadius.zero,
  EdgeInsetsGeometry? padding,
}) {
  //final card = Theme.of(context).cardTheme;
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 1),
   // padding: padding,
   // decoration: BoxDecoration(
    //  color: card.color?.withOpacity(0.5),
    //  borderRadius: borderRadius,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
  //  ),
    child: Padding(
      padding: padding ?? EdgeInsets.all(0),
      child: child,
    ),
  );
}

Widget settingsSdkRow(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String label,
  required String detail,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: color.withValues(alpha: 0.15),
          child: FaIcon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(label, style:  GoogleFonts.openSans(fontWeight: FontWeight.w500))),
        Text(detail, style: GoogleFonts.openSans(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
      ],
    ),
  );
}

Widget settingsSdkDivider(BuildContext context) => Divider(
  height: 1,
  thickness: 0.5,
  color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
);
