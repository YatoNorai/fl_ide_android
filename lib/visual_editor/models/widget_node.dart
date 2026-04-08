import 'dart:math';

/// A node in the visual widget tree.
class WidgetNode {
  final String id;
  final String type;
  Map<String, dynamic> properties;
  List<WidgetNode> children;

  WidgetNode({
    String? id,
    required this.type,
    Map<String, dynamic>? properties,
    List<WidgetNode>? children,
  })  : id = id ?? _uid(),
        properties = properties ?? {},
        children = children ?? [];

  static String _uid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      Random().nextInt(0xFFFF).toRadixString(36);

  // ── Child policy ──────────────────────────────────────────────────────────

  bool get canHaveChildren => _policy != _Policy.leaf;
  bool get canHaveMultipleChildren => _policy == _Policy.multi;

  _Policy get _policy {
    const multi = {
      'Row', 'Column', 'Stack', 'Wrap', 'ListView', 'GridView',
      'CustomScrollView',
    };
    const single = {
      'Container', 'Padding', 'Center', 'Align', 'Expanded', 'Flexible',
      'SizedBox', 'Card', 'ClipRRect', 'ClipOval', 'Opacity',
      'AnimatedContainer', 'ConstrainedBox', 'AspectRatio', 'FittedBox',
      'Scaffold', 'SafeArea', 'SingleChildScrollView', 'InkWell',
      'GestureDetector', 'Hero', 'Material', 'DecoratedBox', 'LimitedBox',
      'OverflowBox', 'Tooltip',
    };
    if (multi.contains(type)) return _Policy.multi;
    if (single.contains(type)) return _Policy.single;
    return _Policy.leaf;
  }

  // ── Code generation ───────────────────────────────────────────────────────

  String toCode([int indent = 0]) {
    final p = '  ' * indent;
    final p1 = '  ' * (indent + 1);
    final p2 = '  ' * (indent + 2);

    String prop(String k, [String? fallback]) {
      final v = properties[k];
      return v != null ? v.toString() : (fallback ?? '');
    }

    bool hasProp(String k) => properties.containsKey(k) && properties[k] != null;

    String childCode([int extraIndent = 0]) {
      if (children.isEmpty) return '${p1}const SizedBox.shrink()';
      return children.first.toCode(indent + 1 + extraIndent);
    }

    String childrenCode() => children.isEmpty
        ? ''
        : children.map((c) => c.toCode(indent + 1)).join(',\n');

    switch (type) {
      // ── Multi-child layouts ─────────────────────────────────────────────

      case 'Row':
      case 'Column':
        final main = prop('mainAxisAlignment', 'MainAxisAlignment.start');
        final cross = prop('crossAxisAlignment', 'CrossAxisAlignment.center');
        final items = childrenCode();
        return '${p}$type(\n'
            '${p1}mainAxisAlignment: $main,\n'
            '${p1}crossAxisAlignment: $cross,\n'
            '${p1}children: [\n'
            '${items.isEmpty ? '' : '$items,\n'}'
            '${p1}],\n'
            '${p})';

      case 'Stack':
        final align = prop('alignment', 'AlignmentDirectional.topStart');
        final items = childrenCode();
        return '${p}Stack(\n'
            '${p1}alignment: $align,\n'
            '${p1}children: [\n'
            '${items.isEmpty ? '' : '$items,\n'}'
            '${p1}],\n'
            '${p})';

      case 'Wrap':
        final spacing = prop('spacing', '8.0');
        final runSpacing = prop('runSpacing', '8.0');
        final items = childrenCode();
        return '${p}Wrap(\n'
            '${p1}spacing: $spacing,\n'
            '${p1}runSpacing: $runSpacing,\n'
            '${p1}children: [\n'
            '${items.isEmpty ? '' : '$items,\n'}'
            '${p1}],\n'
            '${p})';

      case 'ListView':
        final items = childrenCode();
        return '${p}ListView(\n'
            '${p1}children: [\n'
            '${items.isEmpty ? '' : '$items,\n'}'
            '${p1}],\n'
            '${p})';

      // ── Single-child layouts ────────────────────────────────────────────

      case 'Container': {
        final lines = <String>[];
        if (hasProp('width')) lines.add('${p1}width: ${prop('width')},');
        if (hasProp('height')) lines.add('${p1}height: ${prop('height')},');
        if (hasProp('color') && !hasProp('borderRadius')) {
          lines.add('${p1}color: ${prop('color')},');
        }
        if (hasProp('padding')) {
          lines.add('${p1}padding: const EdgeInsets.all(${prop('padding')}),');
        }
        if (hasProp('borderRadius')) {
          final br = prop('borderRadius');
          final clr = hasProp('color') ? '\n${p2}color: ${prop('color')},' : '';
          lines.add('${p1}decoration: BoxDecoration($clr\n${p2}borderRadius: BorderRadius.circular($br),\n${p1}),');
        }
        if (children.isNotEmpty) {
          lines.add('${p1}child: ${children.first.toCode(indent + 1).trimLeft()},');
        }
        return '${p}Container(\n${lines.join('\n')}\n${p})';
      }

      case 'Padding':
        return '${p}Padding(\n'
            '${p1}padding: const EdgeInsets.all(${prop('padding', '8.0')}),\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'Center':
        return '${p}Center(\n${p1}child: ${childCode()},\n${p})';

      case 'Align':
        return '${p}Align(\n'
            '${p1}alignment: ${prop('alignment', 'Alignment.center')},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'Expanded':
        return '${p}Expanded(\n'
            '${p1}flex: ${prop('flex', '1')},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'Flexible':
        return '${p}Flexible(\n'
            '${p1}flex: ${prop('flex', '1')},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'SizedBox':
        final hasChild = children.isNotEmpty;
        final w = hasProp('width') ? '${p1}width: ${prop('width')},\n' : '';
        final h = hasProp('height') ? '${p1}height: ${prop('height')},\n' : '';
        final c = hasChild ? '${p1}child: ${childCode()},\n' : '';
        if (!hasChild && !hasProp('width') && !hasProp('height')) {
          return '${p}const SizedBox.shrink()';
        }
        return '${p}SizedBox(\n$w$h$c${p})';

      case 'Card':
        final el = prop('elevation', '2.0');
        return '${p}Card(\n'
            '${p1}elevation: $el,\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'ClipRRect':
        return '${p}ClipRRect(\n'
            '${p1}borderRadius: BorderRadius.circular(${prop('borderRadius', '8.0')}),\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'ClipOval':
        return '${p}ClipOval(\n${p1}child: ${childCode()},\n${p})';

      case 'Opacity':
        return '${p}Opacity(\n'
            '${p1}opacity: ${prop('opacity', '1.0')},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'SafeArea':
        return '${p}SafeArea(\n${p1}child: ${childCode()},\n${p})';

      case 'SingleChildScrollView':
        return '${p}SingleChildScrollView(\n${p1}child: ${childCode()},\n${p})';

      case 'InkWell':
        return '${p}InkWell(\n'
            '${p1}onTap: () {},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'GestureDetector':
        return '${p}GestureDetector(\n'
            '${p1}onTap: () {},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'Scaffold': {
        final lines = <String>[];
        if (hasProp('appBarTitle')) {
          lines.add("${p1}appBar: AppBar(title: const Text('${prop('appBarTitle')}')),");
        }
        if (children.isNotEmpty) {
          lines.add('${p1}body: ${children.first.toCode(indent + 1).trimLeft()},');
        }
        return '${p}Scaffold(\n${lines.join('\n')}\n${p})';
      }

      case 'Material':
        return '${p}Material(\n'
            '${p1}color: ${prop('color', 'Colors.transparent')},\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      case 'Tooltip':
        return '${p}Tooltip(\n'
            '${p1}message: \'${prop('message', 'Tooltip')}\',\n'
            '${p1}child: ${childCode()},\n'
            '${p})';

      // ── Leaf widgets ────────────────────────────────────────────────────

      case 'Text': {
        final text = prop('text', 'Text');
        final args = <String>[];
        if (hasProp('fontSize')) args.add('fontSize: ${prop('fontSize')}');
        if (hasProp('fontWeight')) args.add('fontWeight: ${prop('fontWeight')}');
        if (hasProp('color')) args.add('color: ${prop('color')}');
        final style = args.isEmpty ? '' : ', style: TextStyle(${args.join(', ')})';
        return "${p}const Text('$text'$style)";
      }

      case 'Icon':
        final ico = prop('icon', 'Icons.star');
        final size = prop('size', '24.0');
        final clr = hasProp('color') ? ', color: ${prop('color')}' : '';
        return '${p}Icon($ico, size: $size$clr)';

      case 'Image':
        return '${p}Image.network(\n'
            "${p1}'${prop('url', 'https://picsum.photos/200')}',\n"
            '${p1}fit: ${prop('fit', 'BoxFit.cover')},\n'
            '${p})';

      case 'FlutterLogo':
        return '${p}FlutterLogo(size: ${prop('size', '48.0')})';

      case 'Placeholder':
        return '${p}const Placeholder()';

      case 'Divider':
        return '${p}const Divider()';

      case 'VerticalDivider':
        return '${p}const VerticalDivider()';

      case 'CircularProgressIndicator':
        return '${p}const CircularProgressIndicator()';

      case 'LinearProgressIndicator':
        return '${p}const LinearProgressIndicator()';

      case 'CircleAvatar': {
        final r = prop('radius', '24.0');
        final bg = hasProp('backgroundColor') ? '${p1}backgroundColor: ${prop('backgroundColor')},\n' : '';
        return '${p}CircleAvatar(\n${bg}${p1}radius: $r,\n${p})';
      }

      case 'ElevatedButton':
        return "${p}ElevatedButton(\n${p1}onPressed: () {},\n${p1}child: const Text('${prop('label', 'Button')}'),\n${p})";

      case 'TextButton':
        return "${p}TextButton(\n${p1}onPressed: () {},\n${p1}child: const Text('${prop('label', 'Button')}'),\n${p})";

      case 'OutlinedButton':
        return "${p}OutlinedButton(\n${p1}onPressed: () {},\n${p1}child: const Text('${prop('label', 'Button')}'),\n${p})";

      case 'FilledButton':
        return "${p}FilledButton(\n${p1}onPressed: () {},\n${p1}child: const Text('${prop('label', 'Button')}'),\n${p})";

      case 'IconButton':
        return '${p}IconButton(\n'
            '${p1}icon: const Icon(${prop('icon', 'Icons.add')}),\n'
            '${p1}onPressed: () {},\n'
            '${p})';

      case 'FloatingActionButton':
        return '${p}FloatingActionButton(\n'
            '${p1}onPressed: () {},\n'
            '${p1}child: const Icon(${prop('icon', 'Icons.add')}),\n'
            '${p})';

      case 'TextField':
        final hint = hasProp('hintText') ? "\n${p2}hintText: '${prop('hintText')}'," : '';
        final label = hasProp('labelText') ? "\n${p2}labelText: '${prop('labelText')}'," : '';
        return '${p}TextField(\n'
            '${p1}decoration: const InputDecoration($hint$label\n${p1}),\n'
            '${p})';

      case 'Switch':
        return '${p}Switch(\n${p1}value: false,\n${p1}onChanged: (v) {},\n${p})';

      case 'Checkbox':
        return '${p}Checkbox(\n${p1}value: false,\n${p1}onChanged: (v) {},\n${p})';

      case 'Slider':
        return '${p}Slider(\n'
            '${p1}value: ${prop('value', '0.5')},\n'
            '${p1}onChanged: (v) {},\n'
            '${p})';

      case 'Chip':
        return "${p}Chip(label: const Text('${prop('label', 'Chip')}'))";

      case 'Badge':
        return "${p}Badge(label: const Text('${prop('label', '1')}'))";

      case 'ListTile': {
        final title = prop('title', 'Title');
        final sub = hasProp('subtitle') ? "\n${p1}subtitle: const Text('${prop('subtitle')}')," : '';
        return "${p}ListTile(\n${p1}title: const Text('$title'),$sub\n${p})";
      }

      case 'AppBar':
        return "${p}AppBar(\n${p1}title: const Text('${prop('title', 'AppBar')}'),\n${p})";

      case 'BottomNavigationBar':
        return '${p}BottomNavigationBar(\n'
            '${p1}currentIndex: 0,\n'
            '${p1}onTap: (i) {},\n'
            '${p1}items: const [\n'
            '${p2}BottomNavigationBarItem(icon: Icon(Icons.home), label: \'Home\'),\n'
            '${p2}BottomNavigationBarItem(icon: Icon(Icons.settings), label: \'Settings\'),\n'
            '${p1}],\n'
            '${p})';

      case 'Spacer':
        final flex = prop('flex', '1');
        return flex == '1' ? '${p}const Spacer()' : '${p}Spacer(flex: $flex)';

      default:
        return '${p}const $type()';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  WidgetNode deepCopy() => WidgetNode(
        type: type,
        properties: Map<String, dynamic>.from(properties),
        children: children.map((c) => c.deepCopy()).toList(),
      );

  /// Find a node by id anywhere in the tree.
  WidgetNode? findById(String targetId) {
    if (id == targetId) return this;
    for (final c in children) {
      final found = c.findById(targetId);
      if (found != null) return found;
    }
    return null;
  }

  /// Find parent of a node by child id.
  WidgetNode? findParentOf(String childId) {
    for (final c in children) {
      if (c.id == childId) return this;
      final found = c.findParentOf(childId);
      if (found != null) return found;
    }
    return null;
  }
}

enum _Policy { leaf, single, multi }
