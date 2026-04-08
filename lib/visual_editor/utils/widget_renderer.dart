import 'package:flutter/material.dart';

import '../models/widget_node.dart';

/// Renders a [WidgetNode] tree into real Flutter widgets for live preview.
///
/// All interactive callbacks are no-ops since this is a preview only.
class WidgetRenderer {
  static Widget render(WidgetNode node, {bool isRoot = false}) {
    return _build(node);
  }

  /// Find a child with the given `_slot` property value.
  static WidgetNode? _slotNode(WidgetNode node, String slot) {
    try {
      return node.children.firstWhere((c) => c.properties['_slot'] == slot);
    } catch (_) {
      return null;
    }
  }

  /// Find the first child that has NO `_slot` or whose slot matches [fallback].
  static WidgetNode? _unslottedChild(WidgetNode node) {
    try {
      return node.children.firstWhere((c) => !c.properties.containsKey('_slot'));
    } catch (_) {
      return null;
    }
  }

  /// All children that have no `_slot` (regular children).
  static List<Widget> _unslottedChildren(WidgetNode node) =>
      node.children
          .where((c) => !c.properties.containsKey('_slot'))
          .map(_build)
          .toList();

  static Widget _build(WidgetNode node) {
    final p = node.properties;

    Widget? firstChild() {
      final c = _unslottedChild(node);
      return c != null ? _build(c) : null;
    }

    List<Widget> allChildren() => _unslottedChildren(node);

    switch (node.type) {
      // ── Layout ─────────────────────────────────────────────────────────────

      case 'Row':
        return Row(
          mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
          crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
          children: allChildren(),
        );

      case 'Column':
        return Column(
          mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
          crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
          children: allChildren(),
        );

      case 'Stack':
        return Stack(
          alignment: _alignment(p['alignment']) ?? AlignmentDirectional.topStart,
          children: allChildren(),
        );

      case 'Wrap':
        return Wrap(
          spacing: _d(p['spacing'], 8.0)!,
          runSpacing: _d(p['runSpacing'], 8.0)!,
          children: allChildren(),
        );

      case 'ListView':
        return ListView(children: allChildren());

      case 'GridView':
        return GridView.count(
          crossAxisCount: _i(p['crossAxisCount'], 2),
          children: allChildren(),
        );

      case 'Container': {
        BoxDecoration? deco;
        final color = _color(p['color']);
        final br = _d(p['borderRadius'], null);
        if (br != null || color != null) {
          deco = BoxDecoration(
            color: color,
            borderRadius: br != null ? BorderRadius.circular(br) : null,
          );
        }
        return Container(
          width: _d(p['width'], null),
          height: _d(p['height'], null),
          padding: _ei(p['padding']),
          margin: _ei(p['margin']),
          decoration: deco,
          color: deco == null ? color : null,
          child: firstChild(),
        );
      }

      case 'Padding':
        return Padding(
          padding: _ei(p['padding']) ?? const EdgeInsets.all(8),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Center':
        return Center(child: firstChild() ?? const SizedBox.shrink());

      case 'Align':
        return Align(
          alignment: _alignment(p['alignment']) ?? Alignment.center,
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Expanded':
        return Expanded(
          flex: _i(p['flex'], 1),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Flexible':
        return Flexible(
          flex: _i(p['flex'], 1),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Spacer':
        return Spacer(flex: _i(p['flex'], 1));

      case 'SizedBox':
        return SizedBox(
          width: _d(p['width'], null),
          height: _d(p['height'], null),
          child: firstChild(),
        );

      case 'AspectRatio':
        return AspectRatio(
          aspectRatio: _d(p['aspectRatio'], 1.0)!,
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'FractionallySizedBox':
        return FractionallySizedBox(
          widthFactor: _d(p['widthFactor'], null),
          heightFactor: _d(p['heightFactor'], null),
          child: firstChild(),
        );

      case 'ConstrainedBox':
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: _d(p['maxWidth'], double.infinity)!,
            maxHeight: _d(p['maxHeight'], double.infinity)!,
          ),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'SafeArea':
        return SafeArea(child: firstChild() ?? const SizedBox.shrink());

      case 'SingleChildScrollView':
        return SingleChildScrollView(
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'ClipRRect':
        return ClipRRect(
          borderRadius:
              BorderRadius.circular(_d(p['borderRadius'], 8.0)!),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'ClipOval':
        return ClipOval(child: firstChild() ?? const SizedBox.shrink());

      case 'Opacity':
        return Opacity(
          opacity: _d(p['opacity'], 1.0)!,
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Positioned': {
        final child = firstChild() ?? const SizedBox.shrink();
        return Positioned(
          left: _d(p['left'], null),
          top: _d(p['top'], null),
          right: _d(p['right'], null),
          bottom: _d(p['bottom'], null),
          child: child,
        );
      }

      case 'InkWell':
      case 'GestureDetector':
        return InkWell(
          onTap: () {},
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Card':
        return Card(
          elevation: _d(p['elevation'], 2.0),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Material':
        return Material(
          color: _color(p['color']) ?? Colors.transparent,
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Tooltip':
        return Tooltip(
          message: _s(p['message'], 'Tooltip'),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      case 'Hero':
        return Hero(
          tag: _s(p['tag'], 'hero'),
          child: firstChild() ?? const SizedBox.shrink(),
        );

      // ── Material ────────────────────────────────────────────────────────────

      case 'Scaffold': {
        final appBarNode = _slotNode(node, 'appBar');
        final bodyNode = _slotNode(node, 'body') ?? _unslottedChild(node);
        final fabNode = _slotNode(node, 'floatingActionButton');
        final drawerNode = _slotNode(node, 'drawer');
        final bottomNavNode = _slotNode(node, 'bottomNavigationBar');
        return Scaffold(
          appBar: appBarNode != null
              ? _buildAppBar(appBarNode)
              : p.containsKey('appBarTitle')
                  ? AppBar(title: Text(_s(p['appBarTitle'], 'App')))
                  : null,
          body: bodyNode != null ? _build(bodyNode) : null,
          floatingActionButton:
              fabNode != null ? _build(fabNode) : null,
          drawer: drawerNode != null ? _build(drawerNode) : null,
          bottomNavigationBar:
              bottomNavNode != null ? _build(bottomNavNode) : null,
        );
      }

      case 'AppBar':
        return _buildAppBar(node);

      case 'ListTile': {
        final leadingNode = _slotNode(node, 'leading');
        final trailingNode = _slotNode(node, 'trailing');
        return ListTile(
          title: Text(_s(p['title'], 'Title')),
          subtitle: p.containsKey('subtitle')
              ? Text(_s(p['subtitle'], ''))
              : null,
          leading: leadingNode != null
              ? _build(leadingNode)
              : p.containsKey('icon')
                  ? Icon(_icon(p['icon']))
                  : null,
          trailing: trailingNode != null ? _build(trailingNode) : null,
        );
      }

      case 'CircleAvatar':
        return CircleAvatar(
          radius: _d(p['radius'], 24),
          backgroundColor: _color(p['backgroundColor']),
        );

      case 'Chip':
        return Chip(label: Text(_s(p['label'], 'Chip')));

      case 'Badge':
        return Badge(label: Text(_s(p['label'], '1')));

      case 'Divider':
        return const Divider();

      case 'VerticalDivider':
        return const VerticalDivider();

      case 'BottomNavigationBar':
        return BottomNavigationBar(
          currentIndex: 0,
          onTap: (_) {},
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_outlined), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        );

      case 'NavigationBar':
        return NavigationBar(
          selectedIndex: 0,
          onDestinationSelected: (_) {},
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined), label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ],
        );

      // ── Buttons ─────────────────────────────────────────────────────────────

      case 'ElevatedButton':
        return ElevatedButton(
          onPressed: () {},
          child: Text(_s(p['label'], 'Button')),
        );

      case 'TextButton':
        return TextButton(
          onPressed: () {},
          child: Text(_s(p['label'], 'Button')),
        );

      case 'OutlinedButton':
        return OutlinedButton(
          onPressed: () {},
          child: Text(_s(p['label'], 'Button')),
        );

      case 'FilledButton':
        return FilledButton(
          onPressed: () {},
          child: Text(_s(p['label'], 'Button')),
        );

      case 'IconButton':
        return IconButton(
          icon: Icon(_icon(p['icon'])),
          onPressed: () {},
        );

      case 'FloatingActionButton':
        return FloatingActionButton(
          onPressed: () {},
          child: Icon(_icon(p['icon'])),
        );

      // ── Input ───────────────────────────────────────────────────────────────

      case 'TextField':
        return TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: _s(p['hintText'], null),
            labelText: _s(p['labelText'], null),
            border: const OutlineInputBorder(),
          ),
        );

      case 'Switch':
        return Switch(value: false, onChanged: null);

      case 'Checkbox':
        return Checkbox(value: false, onChanged: null);

      case 'Radio':
        return Radio<int>(value: 0, groupValue: 0, onChanged: null);

      case 'Slider':
        return Slider(
          value: _d(p['value'], 0.5)!.clamp(0.0, 1.0),
          onChanged: null,
        );

      // ── Leaf ────────────────────────────────────────────────────────────────

      case 'Text': {
        final style = (p.containsKey('fontSize') ||
                p.containsKey('fontWeight') ||
                p.containsKey('color'))
            ? TextStyle(
                fontSize: _d(p['fontSize'], null),
                fontWeight: _fontWeight(p['fontWeight']),
                color: _color(p['color']),
              )
            : null;
        return Text(_s(p['text'], 'Text'), style: style);
      }

      case 'Icon':
        return Icon(
          _icon(p['icon']),
          size: _d(p['size'], 24),
          color: _color(p['color']),
        );

      case 'Image':
        return Image.network(
          _s(p['url'], 'https://picsum.photos/200'),
          fit: _boxFit(p['fit']),
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image_outlined),
        );

      case 'FlutterLogo':
        return FlutterLogo(size: _d(p['size'], 48));

      case 'Placeholder':
        return const Placeholder();

      case 'CircularProgressIndicator':
        return const CircularProgressIndicator();

      case 'LinearProgressIndicator':
        return const LinearProgressIndicator();

      // ── Fallback ────────────────────────────────────────────────────────────

      default:
        // Try to render children, otherwise show a labelled placeholder box.
        if (node.children.length == 1) {
          return firstChild()!;
        }
        if (node.children.length > 1) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: allChildren(),
          );
        }
        return _Placeholder(label: node.type);
    }
  }

  // ── AppBar builder ────────────────────────────────────────────────────────

  static PreferredSizeWidget _buildAppBar(WidgetNode node) {
    final p = node.properties;
    final titleNode = _slotNode(node, 'title') ?? _unslottedChild(node);
    final leadingNode = _slotNode(node, 'leading');
    final actionNodes = node.children
        .where((c) => c.properties['_slot'] == 'actions')
        .map(_build)
        .toList();
    return AppBar(
      title: titleNode != null
          ? _build(titleNode)
          : p.containsKey('title')
              ? Text(_s(p['title'], ''))
              : null,
      leading: leadingNode != null ? _build(leadingNode) : null,
      backgroundColor: _color(p['backgroundColor']),
      actions: actionNodes.isNotEmpty ? actionNodes : null,
    );
  }

  // ── Property parsers ───────────────────────────────────────────────────────

  static double? _d(dynamic v, double? fallback) {
    if (v == null) return fallback;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return double.tryParse(v.toString()) ?? fallback;
  }

  static int _i(dynamic v, int fallback) {
    if (v == null) return fallback;
    if (v is int) return v;
    return int.tryParse(v.toString()) ?? fallback;
  }

  static String _s(dynamic v, String? fallback) {
    if (v == null) return fallback ?? '';
    return v.toString();
  }

  static Color? _color(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    // Color(0xFFRRGGBB)
    final hexMatch = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)').firstMatch(s);
    if (hexMatch != null) {
      return Color(int.parse(hexMatch.group(1)!, radix: 16));
    }
    // Colors.xxx or Colors.xxx.shade###
    if (s.startsWith('Colors.')) {
      return _namedColor(s.split('.')[1].split('.')[0]);
    }
    return null;
  }

  static Color? _namedColor(String name) {
    const m = {
      'red': Colors.red,
      'pink': Colors.pink,
      'purple': Colors.purple,
      'deepPurple': Colors.deepPurple,
      'indigo': Colors.indigo,
      'blue': Colors.blue,
      'lightBlue': Colors.lightBlue,
      'cyan': Colors.cyan,
      'teal': Colors.teal,
      'green': Colors.green,
      'lightGreen': Colors.lightGreen,
      'lime': Colors.lime,
      'yellow': Colors.yellow,
      'amber': Colors.amber,
      'orange': Colors.orange,
      'deepOrange': Colors.deepOrange,
      'brown': Colors.brown,
      'grey': Colors.grey,
      'blueGrey': Colors.blueGrey,
      'black': Colors.black,
      'white': Colors.white,
      'transparent': Colors.transparent,
    };
    return m[name];
  }

  static EdgeInsets? _ei(dynamic v) {
    if (v == null) return null;
    final n = _d(v, null);
    if (n != null) return EdgeInsets.all(n);
    return null;
  }

  static MainAxisAlignment _mainAxis(dynamic v) {
    switch (v?.toString()) {
      case 'MainAxisAlignment.center': return MainAxisAlignment.center;
      case 'MainAxisAlignment.end': return MainAxisAlignment.end;
      case 'MainAxisAlignment.spaceBetween': return MainAxisAlignment.spaceBetween;
      case 'MainAxisAlignment.spaceAround': return MainAxisAlignment.spaceAround;
      case 'MainAxisAlignment.spaceEvenly': return MainAxisAlignment.spaceEvenly;
      default: return MainAxisAlignment.start;
    }
  }

  static CrossAxisAlignment _crossAxis(dynamic v) {
    switch (v?.toString()) {
      case 'CrossAxisAlignment.start': return CrossAxisAlignment.start;
      case 'CrossAxisAlignment.end': return CrossAxisAlignment.end;
      case 'CrossAxisAlignment.stretch': return CrossAxisAlignment.stretch;
      case 'CrossAxisAlignment.baseline': return CrossAxisAlignment.baseline;
      default: return CrossAxisAlignment.center;
    }
  }

  static AlignmentGeometry? _alignment(dynamic v) {
    switch (v?.toString()) {
      case 'Alignment.topLeft': return Alignment.topLeft;
      case 'Alignment.topCenter': return Alignment.topCenter;
      case 'Alignment.topRight': return Alignment.topRight;
      case 'Alignment.centerLeft': return Alignment.centerLeft;
      case 'Alignment.center': return Alignment.center;
      case 'Alignment.centerRight': return Alignment.centerRight;
      case 'Alignment.bottomLeft': return Alignment.bottomLeft;
      case 'Alignment.bottomCenter': return Alignment.bottomCenter;
      case 'Alignment.bottomRight': return Alignment.bottomRight;
      default: return null;
    }
  }

  static FontWeight? _fontWeight(dynamic v) {
    switch (v?.toString()) {
      case 'FontWeight.bold': return FontWeight.bold;
      case 'FontWeight.w100': return FontWeight.w100;
      case 'FontWeight.w200': return FontWeight.w200;
      case 'FontWeight.w300': return FontWeight.w300;
      case 'FontWeight.w400': return FontWeight.w400;
      case 'FontWeight.w500': return FontWeight.w500;
      case 'FontWeight.w600': return FontWeight.w600;
      case 'FontWeight.w700': return FontWeight.w700;
      case 'FontWeight.w800': return FontWeight.w800;
      case 'FontWeight.w900': return FontWeight.w900;
      default: return null;
    }
  }

  static IconData _icon(dynamic v) {
    switch (v?.toString()) {
      case 'Icons.add': return Icons.add;
      case 'Icons.home': case 'Icons.home_outlined': return Icons.home_outlined;
      case 'Icons.settings': case 'Icons.settings_outlined': return Icons.settings_outlined;
      case 'Icons.search': return Icons.search;
      case 'Icons.close': return Icons.close;
      case 'Icons.menu': return Icons.menu;
      case 'Icons.person': return Icons.person;
      case 'Icons.star': return Icons.star;
      case 'Icons.favorite': return Icons.favorite;
      case 'Icons.share': return Icons.share;
      case 'Icons.edit': return Icons.edit;
      case 'Icons.delete': return Icons.delete;
      case 'Icons.check': return Icons.check;
      case 'Icons.info': return Icons.info;
      case 'Icons.warning': return Icons.warning;
      case 'Icons.error': return Icons.error;
      case 'Icons.email': return Icons.email;
      case 'Icons.phone': return Icons.phone;
      case 'Icons.camera': return Icons.camera;
      case 'Icons.image': return Icons.image;
      case 'Icons.send': return Icons.send;
      case 'Icons.notifications': return Icons.notifications;
      case 'Icons.account_circle': return Icons.account_circle;
      case 'Icons.arrow_back': return Icons.arrow_back;
      case 'Icons.arrow_forward': return Icons.arrow_forward;
      default: return Icons.widgets_outlined;
    }
  }

  static BoxFit _boxFit(dynamic v) {
    switch (v?.toString()) {
      case 'BoxFit.contain': return BoxFit.contain;
      case 'BoxFit.fill': return BoxFit.fill;
      case 'BoxFit.fitWidth': return BoxFit.fitWidth;
      case 'BoxFit.fitHeight': return BoxFit.fitHeight;
      case 'BoxFit.none': return BoxFit.none;
      case 'BoxFit.scaleDown': return BoxFit.scaleDown;
      default: return BoxFit.cover;
    }
  }
}

// ── Fallback placeholder ───────────────────────────────────────────────────────

class _Placeholder extends StatelessWidget {
  final String label;
  const _Placeholder({required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(6),
        color: cs.surfaceContainerHighest,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: cs.onSurfaceVariant,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
