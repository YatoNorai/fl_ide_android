import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/flutter_widget_catalog.dart';
import '../models/widget_node.dart';
import '../providers/visual_editor_provider.dart';

// ── Public entry point ────────────────────────────────────────────────────────

/// Renders [node] as a real Flutter widget tree where each widget node
/// is selectable (tap), draggable (long-press), and can receive drops.
/// The [VisualEditorProvider] must be in scope above this widget.
Widget renderInteractive(WidgetNode node, BuildContext context) {
  return _renderDispatch(node, context);
}

// ── Dispatch: handle ParentData widgets specially ─────────────────────────────

Widget _renderDispatch(WidgetNode node, BuildContext context) {
  switch (node.type) {
    case 'Expanded':
      return Expanded(
        flex: _i(node.properties['flex'], 1),
        child: _IWrap(node: node, child: _renderContent(node, context)),
      );

    case 'Flexible':
      return Flexible(
        flex: _i(node.properties['flex'], 1),
        child: _IWrap(node: node, child: _renderContent(node, context)),
      );

    case 'Spacer':
      // Spacer is invisible — no interaction wrapper needed
      return Spacer(flex: _i(node.properties['flex'], 1));

    case 'Positioned': {
      final p = node.properties;
      return Positioned(
        left: _d(p['left'], null),
        top: _d(p['top'], null),
        right: _d(p['right'], null),
        bottom: _d(p['bottom'], null),
        child: _IWrap(node: node, child: _renderContent(node, context)),
      );
    }

    default:
      return _IWrap(node: node, child: _renderContent(node, context));
  }
}

// ── Slot helpers ──────────────────────────────────────────────────────────────

WidgetNode? _slotNode(WidgetNode node, String slot) {
  try {
    return node.children.firstWhere((c) => c.properties['_slot'] == slot);
  } catch (_) {
    return null;
  }
}

List<WidgetNode> _unslottedChildren(WidgetNode node) =>
    node.children.where((c) => !c.properties.containsKey('_slot')).toList();

WidgetNode? _firstUnslottedChild(WidgetNode node) {
  final list = _unslottedChildren(node);
  return list.isEmpty ? null : list.first;
}

// ── Content renderer ──────────────────────────────────────────────────────────

Widget _renderContent(WidgetNode node, BuildContext context) {
  final p = node.properties;

  Widget interactiveChild(WidgetNode child) => renderInteractive(child, context);

  Widget firstChildOrSlot() {
    final c = _firstUnslottedChild(node);
    return c != null ? interactiveChild(c) : _EmptySlot(node: node);
  }

  List<Widget> interactiveChildren() {
    final kids = _unslottedChildren(node);
    return kids.isEmpty
        ? [_EmptySlot(node: node)]
        : kids.map(interactiveChild).toList();
  }

  switch (node.type) {
    // ── Multi-child layouts ───────────────────────────────────────────────────

    case 'Row':
      return Row(
        mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
        crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
        mainAxisSize: MainAxisSize.min,
        children: interactiveChildren(),
      );

    case 'Column':
      return Column(
        mainAxisAlignment: _mainAxis(p['mainAxisAlignment']),
        crossAxisAlignment: _crossAxis(p['crossAxisAlignment']),
        mainAxisSize: MainAxisSize.min,
        children: interactiveChildren(),
      );

    case 'Stack':
      return Stack(
        alignment: _alignment(p['alignment']) ?? AlignmentDirectional.topStart,
        children: interactiveChildren(),
      );

    case 'Wrap':
      return Wrap(
        spacing: _d(p['spacing'], 8.0)!,
        runSpacing: _d(p['runSpacing'], 8.0)!,
        children: interactiveChildren(),
      );

    case 'ListView': {
      final kids = _unslottedChildren(node);
      return ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: kids.isEmpty
            ? [_EmptySlot(node: node)]
            : kids.map(interactiveChild).toList(),
      );
    }

    // ── Single-child layouts ──────────────────────────────────────────────────

    case 'Container': {
      final color = _color(p['color']);
      final br = _d(p['borderRadius'], null);
      BoxDecoration? deco;
      if (br != null) {
        deco = BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(br),
        );
      }
      return Container(
        width: _d(p['width'], null),
        height: _d(p['height'], null),
        padding: _ei(p['padding']),
        color: deco == null ? color : null,
        decoration: deco,
        child: firstChildOrSlot(),
      );
    }

    case 'Padding':
      return Padding(
        padding: _ei(p['padding']) ?? const EdgeInsets.all(8),
        child: firstChildOrSlot(),
      );

    case 'Center':
      return Center(child: firstChildOrSlot());

    case 'Align':
      return Align(
        alignment: _alignment(p['alignment']) ?? Alignment.center,
        child: firstChildOrSlot(),
      );

    case 'SizedBox': {
      final c = _firstUnslottedChild(node);
      return SizedBox(
        width: _d(p['width'], null),
        height: _d(p['height'], null),
        child: c != null ? interactiveChild(c) : null,
      );
    }

    case 'Card':
      return Card(
        elevation: _d(p['elevation'], 2.0),
        child: firstChildOrSlot(),
      );

    case 'ClipRRect':
      return ClipRRect(
        borderRadius: BorderRadius.circular(_d(p['borderRadius'], 8.0)!),
        child: firstChildOrSlot(),
      );

    case 'ClipOval':
      return ClipOval(child: firstChildOrSlot());

    case 'Opacity':
      return Opacity(
        opacity: (_d(p['opacity'], 1.0)!).clamp(0.0, 1.0),
        child: firstChildOrSlot(),
      );

    case 'SafeArea':
      return SafeArea(child: firstChildOrSlot());

    case 'SingleChildScrollView':
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: firstChildOrSlot(),
      );

    case 'InkWell':
    case 'GestureDetector':
      return InkWell(onTap: null, child: firstChildOrSlot());

    case 'Hero':
      return Hero(
        tag: _s(p['tag'], 'hero'),
        child: firstChildOrSlot(),
      );

    case 'Material':
      return Material(
        color: _color(p['color']) ?? Colors.transparent,
        child: firstChildOrSlot(),
      );

    case 'Tooltip':
      return Tooltip(
        message: _s(p['message'], 'Tooltip'),
        child: firstChildOrSlot(),
      );

    // ── Scaffold (slot-aware, special handling) ───────────────────────────────

    case 'Scaffold':
      return _buildInteractiveScaffold(node, context);

    case 'AppBar':
      // Render as a standalone widget in an IgnorePointer so the
      // preferred-size contract is satisfied when used outside a Scaffold slot.
      return SizedBox(
        height: kToolbarHeight,
        child: _buildInteractiveAppBar(node),
      );

    // ── Leaf widgets ──────────────────────────────────────────────────────────

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
      return Placeholder(color: Colors.grey.withAlpha(100));

    case 'CircularProgressIndicator':
      return const CircularProgressIndicator();

    case 'LinearProgressIndicator':
      return const LinearProgressIndicator();

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

    case 'ElevatedButton':
      return ElevatedButton(
        onPressed: null,
        child: Text(_s(p['label'], 'Button')),
      );

    case 'TextButton':
      return TextButton(
        onPressed: null,
        child: Text(_s(p['label'], 'Button')),
      );

    case 'OutlinedButton':
      return OutlinedButton(
        onPressed: null,
        child: Text(_s(p['label'], 'Button')),
      );

    case 'FilledButton':
      return FilledButton(
        onPressed: null,
        child: Text(_s(p['label'], 'Button')),
      );

    case 'IconButton':
      return IconButton(
        icon: Icon(_icon(p['icon'])),
        onPressed: null,
      );

    case 'FloatingActionButton':
      return FloatingActionButton(
        onPressed: null,
        child: Icon(_icon(p['icon'])),
      );

    case 'TextField': {
      final hint = _s(p['hintText'], null);
      final label = _s(p['labelText'], null);
      return TextField(
        enabled: false,
        decoration: InputDecoration(
          hintText: hint.isEmpty ? null : hint,
          labelText: label.isEmpty ? null : label,
          border: const OutlineInputBorder(),
        ),
      );
    }

    case 'Switch':
      return Switch(value: false, onChanged: null);

    case 'Checkbox':
      return Checkbox(value: false, onChanged: null);

    case 'Slider':
      return Slider(
        value: (_d(p['value'], 0.5)!).clamp(0.0, 1.0),
        onChanged: null,
      );

    case 'ListTile': {
      final leadingNode = _slotNode(node, 'leading');
      final trailingNode = _slotNode(node, 'trailing');
      return ListTile(
        title: Text(_s(p['title'], 'Title')),
        subtitle:
            p.containsKey('subtitle') ? Text(_s(p['subtitle'], '')) : null,
        leading: leadingNode != null
            ? interactiveChild(leadingNode)
            : p.containsKey('icon')
                ? Icon(_icon(p['icon']))
                : null,
        trailing:
            trailingNode != null ? interactiveChild(trailingNode) : null,
      );
    }

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

    default:
      return _UnknownWidget(type: node.type);
  }
}

// ── Scaffold builder ──────────────────────────────────────────────────────────

Widget _buildInteractiveScaffold(WidgetNode node, BuildContext context) {
  final p = node.properties;
  final appBarNode = _slotNode(node, 'appBar');
  final fabNode = _slotNode(node, 'floatingActionButton');
  final bottomNavNode = _slotNode(node, 'bottomNavigationBar');
  final bodyNode = _firstUnslottedChild(node);

  return Scaffold(
    appBar: appBarNode != null
        ? _buildInteractiveAppBar(appBarNode)
        : p.containsKey('appBarTitle')
            ? AppBar(title: Text(_s(p['appBarTitle'], 'App')))
            : null,
    body: _ScaffoldBodySlot(node: node, bodyNode: bodyNode),
    floatingActionButton:
        fabNode != null ? renderInteractive(fabNode, context) : null,
    bottomNavigationBar:
        bottomNavNode != null ? renderInteractive(bottomNavNode, context) : null,
  );
}

PreferredSizeWidget _buildInteractiveAppBar(WidgetNode node) {
  final p = node.properties;
  return AppBar(
    title: Text(_s(p['title'], 'AppBar')),
    backgroundColor: _color(p['backgroundColor']),
  );
}

// ── Scaffold body slot ────────────────────────────────────────────────────────

class _ScaffoldBodySlot extends StatefulWidget {
  final WidgetNode node;
  final WidgetNode? bodyNode;

  const _ScaffoldBodySlot({required this.node, this.bodyNode});

  @override
  State<_ScaffoldBodySlot> createState() => _ScaffoldBodySlotState();
}

class _ScaffoldBodySlotState extends State<_ScaffoldBodySlot> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<VisualEditorProvider>();

    if (widget.bodyNode != null) {
      return Builder(
        builder: (ctx) => renderInteractive(widget.bodyNode!, ctx),
      );
    }

    final color = defForType(widget.node.type)?.color ?? cs.primary;

    return DragTarget<FlutterWidgetDef>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final def = details.data;
        final newNode = WidgetNode(
          type: def.name,
          properties: Map<String, dynamic>.from(def.defaultProperties),
        );
        provider.addWidget(newNode, parentId: widget.node.id);
      },
      onMove: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onLeave: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      builder: (ctx, defCands, _) {
        return DragTarget<WidgetNode>(
          onWillAcceptWithDetails: (details) =>
              details.data.id != widget.node.id,
          onAcceptWithDetails: (details) {
            final dragged = details.data;
            if (dragged.id == widget.node.id) return;
            provider.moveWidget(dragged.id, widget.node.id);
          },
          onMove: (_) {
            if (!_hovering) setState(() => _hovering = true);
          },
          onLeave: (_) {
            if (_hovering) setState(() => _hovering = false);
          },
          builder: (ctx2, nodeCands, _) {
            final anyHover =
                defCands.isNotEmpty || nodeCands.isNotEmpty || _hovering;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              color:
                  anyHover ? color.withAlpha(20) : cs.surfaceContainerLow,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_box_outlined,
                      color: anyHover ? color : cs.outlineVariant,
                      size: 32,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Drop body widget here',
                      style: TextStyle(
                        fontSize: 12,
                        color: anyHover ? color : cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// ── _IWrap: interactive overlay wrapper ───────────────────────────────────────
//
// Layer order (outermost → innermost):
//   DragTarget<FlutterWidgetDef>
//     └─ DragTarget<WidgetNode>
//         └─ LongPressDraggable<WidgetNode>
//             └─ GestureDetector(onTap: select)
//                 └─ DecoratedBox(foreground selection border)
//                     └─ AbsorbPointer
//                         └─ child (real widget content)

class _IWrap extends StatefulWidget {
  final WidgetNode node;
  final Widget child;

  const _IWrap({required this.node, required this.child});

  @override
  State<_IWrap> createState() => _IWrapState();
}

class _IWrapState extends State<_IWrap> {
  bool _defHovering = false;
  bool _nodeHovering = false;

  bool get _isHovered => _defHovering || _nodeHovering;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();
    final isSelected = provider.selectedId == widget.node.id;
    final node = widget.node;
    final catColor = defForType(node.type)?.color ?? cs.primary;

    // ── Drag feedback ─────────────────────────────────────────────────────────
    final dragFeedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: catColor.withAlpha(230),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              defForType(node.type)?.icon ?? Icons.widgets_outlined,
              size: 14,
              color: Colors.white,
            ),
            const SizedBox(width: 6),
            Text(
              node.type,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    // ── Core: selection border + absorb pointer ───────────────────────────────
    final core = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: isSelected
            ? Border.all(color: cs.primary, width: 2.0)
            : _isHovered
                ? Border.all(color: cs.primary.withAlpha(90), width: 1.5)
                : const Border(),
      ),
      child: AbsorbPointer(
        absorbing: true,
        child: widget.child,
      ),
    );

    // ── Tap + draggable ───────────────────────────────────────────────────────
    final withGestures = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => provider.select(node.id),
      child: LongPressDraggable<WidgetNode>(
        data: node,
        feedback: dragFeedback,
        childWhenDragging: Opacity(opacity: 0.25, child: widget.child),
        onDragStarted: () => HapticFeedback.lightImpact(),
        child: core,
      ),
    );

    // ── WidgetNode reparent drop target ───────────────────────────────────────
    final withNodeDrop = node.canHaveChildren
        ? DragTarget<WidgetNode>(
            onWillAcceptWithDetails: (details) {
              final dragged = details.data;
              if (dragged.id == node.id) return false;
              // Prevent dropping an ancestor onto its own descendant
              if (dragged.findById(node.id) != null) return false;
              return true;
            },
            onAcceptWithDetails: (details) {
              final dragged = details.data;
              if (dragged.id == node.id) return;
              provider.moveWidget(dragged.id, node.id);
            },
            onMove: (_) {
              if (!_nodeHovering) setState(() => _nodeHovering = true);
            },
            onLeave: (_) {
              if (_nodeHovering) setState(() => _nodeHovering = false);
            },
            builder: (_, __, ___) => withGestures,
          )
        : withGestures;

    // ── FlutterWidgetDef palette drop target ──────────────────────────────────
    final withDefDrop = node.canHaveChildren
        ? DragTarget<FlutterWidgetDef>(
            onWillAcceptWithDetails: (_) => true,
            onAcceptWithDetails: (details) {
              final def = details.data;
              final newNode = WidgetNode(
                type: def.name,
                properties:
                    Map<String, dynamic>.from(def.defaultProperties),
              );
              provider.addWidget(newNode, parentId: node.id);
            },
            onMove: (_) {
              if (!_defHovering) setState(() => _defHovering = true);
            },
            onLeave: (_) {
              if (_defHovering) setState(() => _defHovering = false);
            },
            builder: (_, __, ___) => withNodeDrop,
          )
        : withNodeDrop;

    return withDefDrop;
  }
}

// ── _EmptySlot ────────────────────────────────────────────────────────────────

class _EmptySlot extends StatefulWidget {
  final WidgetNode node;

  const _EmptySlot({required this.node});

  @override
  State<_EmptySlot> createState() => _EmptySlotState();
}

class _EmptySlotState extends State<_EmptySlot> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.read<VisualEditorProvider>();
    final color = defForType(widget.node.type)?.color ?? cs.primary;

    Widget slotBox({required bool hover}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minWidth: 56, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hover ? color.withAlpha(20) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: hover ? color.withAlpha(180) : color.withAlpha(70),
            width: hover ? 1.5 : 1.0,
          ),
        ),
        child: Center(
          child: Text(
            'drop here',
            style: TextStyle(
              fontSize: 9,
              fontStyle: FontStyle.italic,
              color: hover ? color : color.withAlpha(100),
            ),
          ),
        ),
      );
    }

    return DragTarget<FlutterWidgetDef>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        final def = details.data;
        final newNode = WidgetNode(
          type: def.name,
          properties: Map<String, dynamic>.from(def.defaultProperties),
        );
        provider.addWidget(newNode, parentId: widget.node.id);
      },
      onMove: (_) {
        if (!_hovering) setState(() => _hovering = true);
      },
      onLeave: (_) {
        if (_hovering) setState(() => _hovering = false);
      },
      builder: (ctx, defCands, _) {
        return DragTarget<WidgetNode>(
          onWillAcceptWithDetails: (details) =>
              details.data.id != widget.node.id,
          onAcceptWithDetails: (details) {
            final dragged = details.data;
            if (dragged.id == widget.node.id) return;
            provider.moveWidget(dragged.id, widget.node.id);
          },
          onMove: (_) {
            if (!_hovering) setState(() => _hovering = true);
          },
          onLeave: (_) {
            if (_hovering) setState(() => _hovering = false);
          },
          builder: (ctx2, nodeCands, _) {
            final anyHover =
                defCands.isNotEmpty || nodeCands.isNotEmpty || _hovering;
            return slotBox(hover: anyHover);
          },
        );
      },
    );
  }
}

// ── _UnknownWidget ────────────────────────────────────────────────────────────

class _UnknownWidget extends StatelessWidget {
  final String type;

  const _UnknownWidget({required this.type});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _DashedBorderPainter(color: cs.outlineVariant),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          type,
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            color: cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── Dashed border painter ─────────────────────────────────────────────────────

class _DashedBorderPainter extends CustomPainter {
  final Color color;

  const _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    const dashW = 4.0;
    const gapW = 3.0;

    void drawDashedLine(Offset start, Offset end) {
      final d = end - start;
      final len = d.distance;
      if (len == 0) return;
      final u = d / len;
      double pos = 0;
      while (pos + dashW <= len) {
        canvas.drawLine(
          start + u * pos,
          start + u * (pos + dashW),
          paint,
        );
        pos += dashW + gapW;
      }
    }

    drawDashedLine(Offset.zero, Offset(size.width, 0));
    drawDashedLine(Offset(size.width, 0), Offset(size.width, size.height));
    drawDashedLine(
        Offset(size.width, size.height), Offset(0, size.height));
    drawDashedLine(Offset(0, size.height), Offset.zero);
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) => old.color != color;
}

// ── Property parsers ──────────────────────────────────────────────────────────

double? _d(dynamic v, double? fallback) {
  if (v == null) return fallback;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

int _i(dynamic v, int fallback) {
  if (v == null) return fallback;
  if (v is int) return v;
  return int.tryParse(v.toString()) ?? fallback;
}

String _s(dynamic v, String? fallback) {
  if (v == null) return fallback ?? '';
  return v.toString();
}

Color? _color(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  final hexMatch = RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)').firstMatch(s);
  if (hexMatch != null) {
    return Color(int.parse(hexMatch.group(1)!, radix: 16));
  }
  if (s.startsWith('Colors.')) {
    return _namedColor(s.split('.')[1].split('.')[0]);
  }
  return null;
}

Color? _namedColor(String name) {
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

EdgeInsets? _ei(dynamic v) {
  if (v == null) return null;
  final n = _d(v, null);
  if (n != null) return EdgeInsets.all(n);
  return null;
}

MainAxisAlignment _mainAxis(dynamic v) {
  switch (v?.toString()) {
    case 'MainAxisAlignment.center':
      return MainAxisAlignment.center;
    case 'MainAxisAlignment.end':
      return MainAxisAlignment.end;
    case 'MainAxisAlignment.spaceBetween':
      return MainAxisAlignment.spaceBetween;
    case 'MainAxisAlignment.spaceAround':
      return MainAxisAlignment.spaceAround;
    case 'MainAxisAlignment.spaceEvenly':
      return MainAxisAlignment.spaceEvenly;
    default:
      return MainAxisAlignment.start;
  }
}

CrossAxisAlignment _crossAxis(dynamic v) {
  switch (v?.toString()) {
    case 'CrossAxisAlignment.start':
      return CrossAxisAlignment.start;
    case 'CrossAxisAlignment.end':
      return CrossAxisAlignment.end;
    case 'CrossAxisAlignment.stretch':
      return CrossAxisAlignment.stretch;
    case 'CrossAxisAlignment.baseline':
      return CrossAxisAlignment.baseline;
    default:
      return CrossAxisAlignment.center;
  }
}

AlignmentGeometry? _alignment(dynamic v) {
  switch (v?.toString()) {
    case 'Alignment.topLeft':
      return Alignment.topLeft;
    case 'Alignment.topCenter':
      return Alignment.topCenter;
    case 'Alignment.topRight':
      return Alignment.topRight;
    case 'Alignment.centerLeft':
      return Alignment.centerLeft;
    case 'Alignment.center':
      return Alignment.center;
    case 'Alignment.centerRight':
      return Alignment.centerRight;
    case 'Alignment.bottomLeft':
      return Alignment.bottomLeft;
    case 'Alignment.bottomCenter':
      return Alignment.bottomCenter;
    case 'Alignment.bottomRight':
      return Alignment.bottomRight;
    default:
      return null;
  }
}

FontWeight? _fontWeight(dynamic v) {
  switch (v?.toString()) {
    case 'FontWeight.bold':
      return FontWeight.bold;
    case 'FontWeight.w100':
      return FontWeight.w100;
    case 'FontWeight.w200':
      return FontWeight.w200;
    case 'FontWeight.w300':
      return FontWeight.w300;
    case 'FontWeight.w400':
      return FontWeight.w400;
    case 'FontWeight.w500':
      return FontWeight.w500;
    case 'FontWeight.w600':
      return FontWeight.w600;
    case 'FontWeight.w700':
      return FontWeight.w700;
    case 'FontWeight.w800':
      return FontWeight.w800;
    case 'FontWeight.w900':
      return FontWeight.w900;
    default:
      return null;
  }
}

IconData _icon(dynamic v) {
  switch (v?.toString()) {
    case 'Icons.add':
      return Icons.add;
    case 'Icons.home':
    case 'Icons.home_outlined':
      return Icons.home_outlined;
    case 'Icons.settings':
    case 'Icons.settings_outlined':
      return Icons.settings_outlined;
    case 'Icons.search':
      return Icons.search;
    case 'Icons.close':
      return Icons.close;
    case 'Icons.menu':
      return Icons.menu;
    case 'Icons.person':
      return Icons.person;
    case 'Icons.star':
      return Icons.star;
    case 'Icons.favorite':
      return Icons.favorite;
    case 'Icons.share':
      return Icons.share;
    case 'Icons.edit':
      return Icons.edit;
    case 'Icons.delete':
      return Icons.delete;
    case 'Icons.check':
      return Icons.check;
    case 'Icons.info':
      return Icons.info;
    case 'Icons.warning':
      return Icons.warning;
    case 'Icons.error':
      return Icons.error;
    case 'Icons.email':
      return Icons.email;
    case 'Icons.phone':
      return Icons.phone;
    case 'Icons.camera':
      return Icons.camera;
    case 'Icons.image':
      return Icons.image;
    case 'Icons.send':
      return Icons.send;
    case 'Icons.notifications':
      return Icons.notifications;
    case 'Icons.account_circle':
      return Icons.account_circle;
    case 'Icons.arrow_back':
      return Icons.arrow_back;
    case 'Icons.arrow_forward':
      return Icons.arrow_forward;
    case 'Icons.lock':
      return Icons.lock;
    case 'Icons.visibility':
      return Icons.visibility;
    case 'Icons.visibility_off':
      return Icons.visibility_off;
    case 'Icons.refresh':
      return Icons.refresh;
    case 'Icons.download':
      return Icons.download;
    case 'Icons.upload':
      return Icons.upload;
    case 'Icons.attach_file':
      return Icons.attach_file;
    case 'Icons.link':
      return Icons.link;
    case 'Icons.copy':
      return Icons.copy;
    case 'Icons.paste':
      return Icons.paste;
    case 'Icons.cut':
      return Icons.cut;
    case 'Icons.undo':
      return Icons.undo;
    case 'Icons.redo':
      return Icons.redo;
    case 'Icons.filter_list':
      return Icons.filter_list;
    case 'Icons.sort':
      return Icons.sort;
    case 'Icons.more_vert':
      return Icons.more_vert;
    case 'Icons.more_horiz':
      return Icons.more_horiz;
    case 'Icons.expand_more':
      return Icons.expand_more;
    case 'Icons.expand_less':
      return Icons.expand_less;
    case 'Icons.chevron_right':
      return Icons.chevron_right;
    case 'Icons.chevron_left':
      return Icons.chevron_left;
    case 'Icons.play_arrow':
      return Icons.play_arrow;
    case 'Icons.pause':
      return Icons.pause;
    case 'Icons.stop':
      return Icons.stop;
    case 'Icons.skip_next':
      return Icons.skip_next;
    case 'Icons.skip_previous':
      return Icons.skip_previous;
    case 'Icons.volume_up':
      return Icons.volume_up;
    case 'Icons.volume_off':
      return Icons.volume_off;
    case 'Icons.brightness_6':
      return Icons.brightness_6;
    case 'Icons.dark_mode':
      return Icons.dark_mode;
    case 'Icons.light_mode':
      return Icons.light_mode;
    case 'Icons.wifi':
      return Icons.wifi;
    case 'Icons.bluetooth':
      return Icons.bluetooth;
    case 'Icons.battery_full':
      return Icons.battery_full;
    case 'Icons.location_on':
      return Icons.location_on;
    case 'Icons.map':
      return Icons.map;
    case 'Icons.shopping_cart':
      return Icons.shopping_cart;
    case 'Icons.payment':
      return Icons.payment;
    case 'Icons.receipt':
      return Icons.receipt;
    case 'Icons.thumb_up':
      return Icons.thumb_up;
    case 'Icons.thumb_down':
      return Icons.thumb_down;
    case 'Icons.comment':
      return Icons.comment;
    case 'Icons.chat':
      return Icons.chat;
    default:
      return Icons.widgets_outlined;
  }
}

BoxFit _boxFit(dynamic v) {
  switch (v?.toString()) {
    case 'BoxFit.contain':
      return BoxFit.contain;
    case 'BoxFit.fill':
      return BoxFit.fill;
    case 'BoxFit.fitWidth':
      return BoxFit.fitWidth;
    case 'BoxFit.fitHeight':
      return BoxFit.fitHeight;
    case 'BoxFit.none':
      return BoxFit.none;
    case 'BoxFit.scaleDown':
      return BoxFit.scaleDown;
    default:
      return BoxFit.cover;
  }
}
