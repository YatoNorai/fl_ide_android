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
  for (final c in node.children) {
    if (c.properties['_slot'] == slot) return c;
  }
  return null;
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

    case 'GridView': {
      final kids = _unslottedChildren(node);
      return GridView.count(
        crossAxisCount: _i(p['crossAxisCount'], 2),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: _d(p['mainAxisSpacing'], 4.0)!,
        crossAxisSpacing: _d(p['crossAxisSpacing'], 4.0)!,
        childAspectRatio: _d(p['childAspectRatio'], 1.0)!,
        children: kids.isEmpty
            ? [_EmptySlot(node: node)]
            : kids.map(interactiveChild).toList(),
      );
    }

    case 'CustomScrollView': {
      final kids = _unslottedChildren(node);
      return CustomScrollView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        slivers: kids.isEmpty
            ? [const SliverToBoxAdapter(child: SizedBox(height: 48))]
            : kids.map(interactiveChild).toList(),
      );
    }

    case 'ReorderableListView': {
      final kids = _unslottedChildren(node);
      return ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (_, __) {},
        children: kids.isEmpty
            ? [const ListTile(key: ValueKey('empty'), title: Text('(empty)'))]
            : kids
                .asMap()
                .entries
                .map((e) => KeyedSubtree(
                      key: ValueKey(e.value.id),
                      child: interactiveChild(e.value),
                    ))
                .toList(),
      );
    }

    case 'ExpansionTile': {
      final kids = _unslottedChildren(node);
      return ExpansionTile(
        title: Text(_s(p['title'], 'Expansion Tile')),
        subtitle: p.containsKey('subtitle')
            ? Text(_s(p['subtitle'], ''))
            : null,
        initiallyExpanded: true,
        children: kids.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('children',
                      style: TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic)),
                )
              ]
            : kids.map(interactiveChild).toList(),
      );
    }

    case 'ExpansionPanelList': {
      final kids = _unslottedChildren(node);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: kids.isEmpty ? [_EmptySlot(node: node)] : kids.map(interactiveChild).toList(),
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

    case 'ColoredBox':
      return ColoredBox(
        color: _color(p['color']) ?? Colors.grey.shade200,
        child: firstChildOrSlot(),
      );

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

    case 'FractionallySizedBox':
      return FractionallySizedBox(
        widthFactor: _d(p['widthFactor'], null),
        heightFactor: _d(p['heightFactor'], null),
        alignment: _alignment(p['alignment']) ?? Alignment.center,
        child: firstChildOrSlot(),
      );

    case 'LimitedBox':
      return LimitedBox(
        maxWidth: _d(p['maxWidth'], double.infinity)!,
        maxHeight: _d(p['maxHeight'], double.infinity)!,
        child: firstChildOrSlot(),
      );

    case 'OverflowBox':
      return OverflowBox(
        maxWidth: _d(p['maxWidth'], null),
        maxHeight: _d(p['maxHeight'], null),
        child: firstChildOrSlot(),
      );

    case 'Card':
      return Card(
        elevation: _d(p['elevation'], 2.0),
        color: _color(p['color']),
        child: firstChildOrSlot(),
      );

    case 'ClipRRect':
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(_d(p['borderRadius'], 8.0)!),
        child: firstChildOrSlot(),
      );

    case 'ClipOval':
      return ClipOval(child: firstChildOrSlot());

    case 'ClipPath':
      return ClipRect(child: firstChildOrSlot());

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

    case 'RefreshIndicator':
      return RefreshIndicator(
        onRefresh: () async {},
        child: firstChildOrSlot(),
      );

    case 'InkWell':
    case 'InkResponse':
    case 'Ink':
      return InkWell(onTap: null, child: firstChildOrSlot());

    case 'GestureDetector':
      return firstChildOrSlot();

    case 'Hero':
      return Hero(
        tag: _s(p['tag'], 'hero_${node.id}'),
        child: firstChildOrSlot(),
      );

    case 'Material':
      return Material(
        color: _color(p['color']) ?? Colors.transparent,
        elevation: _d(p['elevation'], 0.0)!,
        borderRadius: p.containsKey('borderRadius')
            ? BorderRadius.circular(_d(p['borderRadius'], 0.0)!)
            : null,
        child: firstChildOrSlot(),
      );

    case 'PhysicalModel':
      return PhysicalModel(
        color: _color(p['color']) ?? Colors.white,
        elevation: _d(p['elevation'], 4.0)!,
        borderRadius:
            BorderRadius.circular(_d(p['borderRadius'], 0.0)!),
        child: firstChildOrSlot(),
      );

    case 'DecoratedBox': {
      final color = _color(p['color']);
      final br = _d(p['borderRadius'], null);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: br != null ? BorderRadius.circular(br) : null,
        ),
        child: firstChildOrSlot(),
      );
    }

    case 'Tooltip':
      return Tooltip(
        message: _s(p['message'], 'Tooltip'),
        child: firstChildOrSlot(),
      );

    case 'InteractiveViewer':
      return InteractiveViewer(child: firstChildOrSlot());

    case 'Dismissible':
      return Dismissible(
        key: ValueKey(node.id),
        child: firstChildOrSlot(),
      );

    case 'RotatedBox':
      return RotatedBox(
        quarterTurns: _i(p['quarterTurns'], 0),
        child: firstChildOrSlot(),
      );

    case 'Transform':
      return Transform.scale(
        scale: _d(p['scale'], 1.0)!,
        child: firstChildOrSlot(),
      );

    case 'DefaultTextStyle':
      return DefaultTextStyle(
        style: TextStyle(
          fontSize: _d(p['fontSize'], null),
          fontWeight: _fontWeight(p['fontWeight']),
          color: _color(p['color']),
        ),
        child: firstChildOrSlot(),
      );

    case 'Theme':
      return firstChildOrSlot();

    case 'Builder':
    case 'LayoutBuilder':
    case 'RepaintBoundary':
    case 'NotificationListener':
    case 'ScrollConfiguration':
    case 'MediaQuery':
    case 'Directionality':
      return firstChildOrSlot();

    // ── Animated widgets ──────────────────────────────────────────────────────

    case 'AnimatedContainer': {
      final color = _color(p['color']);
      return AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: _d(p['width'], null),
        height: _d(p['height'], null),
        color: color,
        child: firstChildOrSlot(),
      );
    }

    case 'AnimatedOpacity':
      return AnimatedOpacity(
        opacity: (_d(p['opacity'], 1.0)!).clamp(0.0, 1.0),
        duration: const Duration(milliseconds: 300),
        child: firstChildOrSlot(),
      );

    case 'AnimatedPadding':
      return AnimatedPadding(
        padding: _ei(p['padding']) ?? const EdgeInsets.all(8),
        duration: const Duration(milliseconds: 300),
        child: firstChildOrSlot(),
      );

    case 'AnimatedAlign':
      return AnimatedAlign(
        alignment: _alignment(p['alignment']) ?? Alignment.center,
        duration: const Duration(milliseconds: 300),
        child: firstChildOrSlot(),
      );

    case 'AnimatedScale':
      return AnimatedScale(
        scale: _d(p['scale'], 1.0)!,
        duration: const Duration(milliseconds: 300),
        child: firstChildOrSlot(),
      );

    case 'AnimatedRotation':
      return AnimatedRotation(
        turns: _d(p['turns'], 0.0)!,
        duration: const Duration(milliseconds: 300),
        child: firstChildOrSlot(),
      );

    case 'AnimatedSwitcher':
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: firstChildOrSlot(),
      );

    case 'AnimatedCrossFade': {
      final c = _firstUnslottedChild(node);
      return AnimatedCrossFade(
        firstChild: c != null ? interactiveChild(c) : const SizedBox.shrink(),
        secondChild: const SizedBox.shrink(),
        crossFadeState: CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 300),
      );
    }

    case 'TweenAnimationBuilder':
    case 'AnimatedBuilder':
    case 'FutureBuilder':
    case 'StreamBuilder':
    case 'ValueListenableBuilder': {
      final c = _firstUnslottedChild(node);
      if (c != null) return interactiveChild(c);
      return _PlaceholderLabel(
        icon: Icons.play_circle_outline_rounded,
        label: node.type,
      );
    }

    // ── Layout helpers ────────────────────────────────────────────────────────

    case 'ConstrainedBox':
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: _d(p['minWidth'], 0.0)!,
          maxWidth: _d(p['maxWidth'], double.infinity)!,
          minHeight: _d(p['minHeight'], 0.0)!,
          maxHeight: _d(p['maxHeight'], double.infinity)!,
        ),
        child: firstChildOrSlot(),
      );

    case 'AspectRatio':
      return AspectRatio(
        aspectRatio: _d(p['aspectRatio'], 1.0)!,
        child: firstChildOrSlot(),
      );

    case 'FittedBox':
      return FittedBox(
        fit: _boxFit(p['fit']),
        child: firstChildOrSlot(),
      );

    // ── Scaffold & Material structure ─────────────────────────────────────────

    case 'Scaffold':
      return _buildInteractiveScaffold(node, context);

    case 'AppBar':
      return SizedBox(
        height: kToolbarHeight,
        child: _buildInteractiveAppBar(node),
      );

    case 'Drawer':
      return Drawer(child: firstChildOrSlot());

    case 'DrawerHeader':
      return DrawerHeader(
        decoration: BoxDecoration(
          color: _color(p['color']) ?? Colors.blue,
        ),
        child: Text(
          _s(p['title'], 'Drawer Header'),
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );

    case 'NavigationRail':
      return NavigationRail(
        selectedIndex: _i(p['selectedIndex'], 0),
        onDestinationSelected: (_) {},
        labelType: NavigationRailLabelType.all,
        destinations: const [
          NavigationRailDestination(
              icon: Icon(Icons.home_outlined), label: Text('Home')),
          NavigationRailDestination(
              icon: Icon(Icons.settings_outlined), label: Text('Settings')),
        ],
      );

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

    case 'TabBar': {
      final cs = Theme.of(context).colorScheme;
      return Material(
        color: cs.primary,
        child: TabBar(
          controller: null,
          isScrollable: true,
          tabs: const [Tab(text: 'Tab 1'), Tab(text: 'Tab 2'), Tab(text: 'Tab 3')],
        ),
      );
    }

    case 'DefaultTabController': {
      final c = _firstUnslottedChild(node);
      return DefaultTabController(
        length: _i(p['length'], 2),
        child: c != null ? interactiveChild(c) : const SizedBox.shrink(),
      );
    }

    case 'TabBarView': {
      final kids = _unslottedChildren(node);
      return SizedBox(
        height: 200,
        child: kids.isEmpty
            ? _PlaceholderLabel(icon: Icons.tab_outlined, label: 'TabBarView')
            : interactiveChild(kids.first),
      );
    }

    // ── Page view / scrolling ─────────────────────────────────────────────────

    case 'PageView': {
      final kids = _unslottedChildren(node);
      if (kids.isEmpty) {
        return _PlaceholderLabel(icon: Icons.swipe_outlined, label: 'PageView');
      }
      return SizedBox(
        height: 200,
        child: PageView(
          physics: const NeverScrollableScrollPhysics(),
          children: kids.map(interactiveChild).toList(),
        ),
      );
    }

    // ── Leaf widgets ──────────────────────────────────────────────────────────

    case 'Text': {
      final text = _s(p['text'], 'Text');
      final hasStyle = p.containsKey('fontSize') ||
          p.containsKey('fontWeight') ||
          p.containsKey('color');
      final style = hasStyle
          ? TextStyle(
              fontSize: _d(p['fontSize'], null),
              fontWeight: _fontWeight(p['fontWeight']),
              color: _color(p['color']),
            )
          : null;
      return Text(text, style: style);
    }

    case 'SelectableText': {
      final text = _s(p['text'], 'SelectableText');
      return SelectableText(
        text,
        style: TextStyle(
          fontSize: _d(p['fontSize'], null),
          color: _color(p['color']),
        ),
      );
    }

    case 'RichText':
      return RichText(
        text: TextSpan(
          text: _s(p['text'], 'RichText'),
          style: DefaultTextStyle.of(context).style,
        ),
      );

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
      return CircularProgressIndicator(
        value: p.containsKey('value') ? _d(p['value'], null) : null,
        color: _color(p['color']),
      );

    case 'LinearProgressIndicator':
      return LinearProgressIndicator(
        value: p.containsKey('value') ? _d(p['value'], null) : null,
        color: _color(p['color']),
      );

    case 'CircleAvatar':
      return CircleAvatar(
        radius: _d(p['radius'], 24),
        backgroundColor: _color(p['backgroundColor']),
        child: p.containsKey('text')
            ? Text(_s(p['text'], ''), style: const TextStyle(color: Colors.white))
            : null,
      );

    case 'Chip':
      return Chip(label: Text(_s(p['label'], 'Chip')));

    case 'InputChip':
      return InputChip(
        label: Text(_s(p['label'], 'Chip')),
        onDeleted: () {},
      );

    case 'FilterChip':
      return FilterChip(
        label: Text(_s(p['label'], 'Filter')),
        selected: false,
        onSelected: (_) {},
      );

    case 'ActionChip':
      return ActionChip(
        label: Text(_s(p['label'], 'Action')),
        onPressed: () {},
      );

    case 'Badge':
      return Badge(label: Text(_s(p['label'], '1')));

    case 'Divider':
      return Divider(
        thickness: _d(p['thickness'], null),
        color: _color(p['color']),
      );

    case 'VerticalDivider':
      return VerticalDivider(
        thickness: _d(p['thickness'], null),
        color: _color(p['color']),
      );

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

    case 'FilledButton.tonal':
      return FilledButton.tonal(
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

    case 'FloatingActionButton.extended':
      return FloatingActionButton.extended(
        onPressed: null,
        icon: Icon(_icon(p['icon'])),
        label: Text(_s(p['label'], 'FAB')),
      );

    case 'FloatingActionButton.small':
      return FloatingActionButton.small(
        onPressed: null,
        child: Icon(_icon(p['icon'])),
      );

    case 'FloatingActionButton.large':
      return FloatingActionButton.large(
        onPressed: null,
        child: Icon(_icon(p['icon'])),
      );

    case 'ToggleButtons': {
      return IgnorePointer(
        child: ToggleButtons(
          isSelected: const [true, false, false],
          onPressed: (_) {},
          children: const [
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('A')),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('B')),
            Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text('C')),
          ],
        ),
      );
    }

    case 'SegmentedButton': {
      return IgnorePointer(
        child: SegmentedButton<String>(
          selected: const {'a'},
          onSelectionChanged: null,
          segments: const [
            ButtonSegment(value: 'a', label: Text('Option A')),
            ButtonSegment(value: 'b', label: Text('Option B')),
          ],
        ),
      );
    }

    case 'PopupMenuButton':
      return IconButton(
        icon: const Icon(Icons.more_vert),
        onPressed: null,
        tooltip: _s(p['tooltip'], 'Menu'),
      );

    case 'MenuAnchor':
    case 'MenuBar':
      return ElevatedButton(
        onPressed: null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_s(p['label'], 'Menu')),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
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

    case 'TextFormField': {
      final hint = _s(p['hintText'], null);
      final label = _s(p['labelText'], null);
      return TextFormField(
        enabled: false,
        decoration: InputDecoration(
          hintText: hint.isEmpty ? null : hint,
          labelText: label.isEmpty ? null : label,
          border: const OutlineInputBorder(),
        ),
      );
    }

    case 'Form':
      return firstChildOrSlot();

    case 'DropdownButton':
    case 'DropdownButtonFormField':
    case 'DropdownMenu': {
      final hint = _s(p['hint'] ?? p['hintText'] ?? p['label'], 'Select...');
      return IgnorePointer(
        child: InputDecorator(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            isDense: true,
            label: Text(hint),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Value', style: TextStyle(fontSize: 14)),
              Icon(Icons.arrow_drop_down),
            ],
          ),
        ),
      );
    }

    case 'Switch':
      return Switch(value: true, onChanged: null);

    case 'Checkbox':
      return Checkbox(value: true, onChanged: null);

    case 'Slider':
      return Slider(
        value: (_d(p['value'], 0.5)!).clamp(0.0, 1.0),
        onChanged: null,
      );

    case 'RangeSlider':
      return RangeSlider(
        values: const RangeValues(0.2, 0.8),
        onChanged: null,
      );

    case 'ListTile': {
      final leadingNode = _slotNode(node, 'leading');
      final trailingNode = _slotNode(node, 'trailing');
      return ListTile(
        title: Text(_s(p['title'], 'Title')),
        subtitle: p.containsKey('subtitle')
            ? Text(_s(p['subtitle'], ''))
            : null,
        leading: leadingNode != null
            ? interactiveChild(leadingNode)
            : p.containsKey('icon')
                ? Icon(_icon(p['icon']))
                : null,
        trailing:
            trailingNode != null ? interactiveChild(trailingNode) : null,
      );
    }

    case 'RadioListTile':
      return RadioListTile<int>(
        value: 0,
        groupValue: 0,
        onChanged: null,
        title: Text(_s(p['title'], 'Option')),
        subtitle: p.containsKey('subtitle')
            ? Text(_s(p['subtitle'], ''))
            : null,
      );

    case 'CheckboxListTile':
      return CheckboxListTile(
        value: true,
        onChanged: null,
        title: Text(_s(p['title'], 'Check me')),
        subtitle: p.containsKey('subtitle')
            ? Text(_s(p['subtitle'], ''))
            : null,
      );

    case 'SwitchListTile':
      return SwitchListTile(
        value: true,
        onChanged: null,
        title: Text(_s(p['title'], 'Toggle')),
        subtitle: p.containsKey('subtitle')
            ? Text(_s(p['subtitle'], ''))
            : null,
      );

    case 'SearchBar':
      return const IgnorePointer(
        child: SearchBar(
          leading: Icon(Icons.search),
          hintText: 'Search...',
        ),
      );

    case 'SearchAnchor':
      return const IgnorePointer(
        child: SearchBar(
          leading: Icon(Icons.search),
          hintText: 'Search...',
        ),
      );

    default:
      return _UnknownWidget(type: node.type);
  }
}

// ── Scaffold builder ──────────────────────────────────────────────────────────

Widget _buildInteractiveScaffold(WidgetNode node, BuildContext context) {
  final p = node.properties;
  // Body may come from the 'body' slot (parsed from Dart) OR as the first unslotted child
  final appBarNode = _slotNode(node, 'appBar');
  final fabNode = _slotNode(node, 'floatingActionButton');
  final bottomNavNode = _slotNode(node, 'bottomNavigationBar');
  final drawerNode = _slotNode(node, 'drawer');
  final bodyNode = _slotNode(node, 'body') ?? _firstUnslottedChild(node);

  return Scaffold(
    appBar: appBarNode != null
        ? _buildInteractiveAppBar(appBarNode)
        : p.containsKey('appBarTitle')
            ? AppBar(title: Text(_s(p['appBarTitle'], 'App')))
            : null,
    drawer: drawerNode != null
        ? renderInteractive(drawerNode, context)
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
  final _hovering = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovering.dispose();
    super.dispose();
  }

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
        if (!_hovering.value) _hovering.value = true;
      },
      onLeave: (_) {
        if (_hovering.value) _hovering.value = false;
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
            if (!_hovering.value) _hovering.value = true;
          },
          onLeave: (_) {
            if (_hovering.value) _hovering.value = false;
          },
          builder: (ctx2, nodeCands, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _hovering,
              builder: (_, isHovering, __) {
                final anyHover =
                    defCands.isNotEmpty || nodeCands.isNotEmpty || isHovering;
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
      },
    );
  }
}

// ── _PlaceholderLabel ─────────────────────────────────────────────────────────

class _PlaceholderLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PlaceholderLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cs.outlineVariant),
        color: cs.surfaceContainerLow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ── _IWrap: interactive overlay wrapper ───────────────────────────────────────

class _IWrap extends StatefulWidget {
  final WidgetNode node;
  final Widget child;

  const _IWrap({required this.node, required this.child});

  @override
  State<_IWrap> createState() => _IWrapState();
}

class _IWrapState extends State<_IWrap> {
  final _defHovering = ValueNotifier<bool>(false);
  final _nodeHovering = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _defHovering.dispose();
    _nodeHovering.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();
    final isSelected = provider.selectedId == widget.node.id;
    final node = widget.node;
    final catColor = defForType(node.type)?.color ?? cs.primary;

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

    // Only the border decoration reacts to hover — wrap just that part so
    // the heavy child subtree is not rebuilt on every drag-move event.
    final core = ValueListenableBuilder<bool>(
      valueListenable: _defHovering,
      builder: (_, defHov, __) => ValueListenableBuilder<bool>(
        valueListenable: _nodeHovering,
        builder: (_, nodeHov, __) {
          final isHovered = defHov || nodeHov;
          return DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: isSelected
                  ? Border.all(color: cs.primary, width: 2.0)
                  : isHovered
                      ? Border.all(color: cs.primary.withAlpha(90), width: 1.5)
                      : const Border(),
            ),
            child: AbsorbPointer(
              absorbing: true,
              child: widget.child,
            ),
          );
        },
      ),
    );

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

    final withNodeDrop = node.canHaveChildren
        ? DragTarget<WidgetNode>(
            onWillAcceptWithDetails: (details) {
              final dragged = details.data;
              if (dragged.id == node.id) return false;
              if (dragged.findById(node.id) != null) return false;
              return true;
            },
            onAcceptWithDetails: (details) {
              final dragged = details.data;
              if (dragged.id == node.id) return;
              provider.moveWidget(dragged.id, node.id);
            },
            onMove: (_) {
              if (!_nodeHovering.value) _nodeHovering.value = true;
            },
            onLeave: (_) {
              if (_nodeHovering.value) _nodeHovering.value = false;
            },
            builder: (_, __, ___) => withGestures,
          )
        : withGestures;

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
              if (!_defHovering.value) _defHovering.value = true;
            },
            onLeave: (_) {
              if (_defHovering.value) _defHovering.value = false;
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
  final _hovering = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _hovering.dispose();
    super.dispose();
  }

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
        if (!_hovering.value) _hovering.value = true;
      },
      onLeave: (_) {
        if (_hovering.value) _hovering.value = false;
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
            if (!_hovering.value) _hovering.value = true;
          },
          onLeave: (_) {
            if (_hovering.value) _hovering.value = false;
          },
          builder: (ctx2, nodeCands, _) {
            return ValueListenableBuilder<bool>(
              valueListenable: _hovering,
              builder: (_, isHovering, __) {
                final anyHover =
                    defCands.isNotEmpty || nodeCands.isNotEmpty || isHovering;
                return slotBox(hover: anyHover);
              },
            );
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
    drawDashedLine(Offset(size.width, size.height), Offset(0, size.height));
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
    final parts = s.split('.');
    final name = parts.length > 1 ? parts[1] : '';
    final shade = parts.length > 2 ? int.tryParse(parts[2]) : null;
    final base = _namedColor(name);
    if (base != null && shade != null && base is MaterialColor) {
      return base[shade];
    }
    return base;
  }
  if (s.startsWith('Color(0x')) {
    final hex = RegExp(r'0x([0-9A-Fa-f]+)').firstMatch(s);
    if (hex != null) return Color(int.parse(hex.group(1)!, radix: 16));
  }
  return null;
}

Color? _namedColor(String name) {
  const m = <String, Color>{
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
    'primaryColor': Colors.blue,
    'primaryColorDark': Colors.blue,
    'accentColor': Colors.blueAccent,
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
    case 'FontWeight.w700':
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
    case 'FontWeight.w800':
      return FontWeight.w800;
    case 'FontWeight.w900':
      return FontWeight.w900;
    default:
      return null;
  }
}

IconData _icon(dynamic v) {
  final s = v?.toString() ?? '';
  // Strip 'Icons.' prefix and look up
  final name = s.startsWith('Icons.') ? s.substring(6) : s;
  const m = <String, IconData>{
    'add': Icons.add,
    'add_circle': Icons.add_circle,
    'add_circle_outline': Icons.add_circle_outline,
    'remove': Icons.remove,
    'close': Icons.close,
    'check': Icons.check,
    'check_circle': Icons.check_circle,
    'home': Icons.home,
    'home_outlined': Icons.home_outlined,
    'settings': Icons.settings,
    'settings_outlined': Icons.settings_outlined,
    'search': Icons.search,
    'menu': Icons.menu,
    'more_vert': Icons.more_vert,
    'more_horiz': Icons.more_horiz,
    'person': Icons.person,
    'person_outline': Icons.person_outline,
    'star': Icons.star,
    'star_border': Icons.star_border,
    'favorite': Icons.favorite,
    'favorite_border': Icons.favorite_border,
    'share': Icons.share,
    'edit': Icons.edit,
    'edit_outlined': Icons.edit_outlined,
    'delete': Icons.delete,
    'delete_outline': Icons.delete_outline,
    'info': Icons.info,
    'info_outline': Icons.info_outline,
    'warning': Icons.warning,
    'error': Icons.error,
    'email': Icons.email,
    'email_outlined': Icons.email_outlined,
    'phone': Icons.phone,
    'camera': Icons.camera,
    'camera_alt': Icons.camera_alt,
    'image': Icons.image,
    'image_outlined': Icons.image_outlined,
    'send': Icons.send,
    'notifications': Icons.notifications,
    'notifications_outlined': Icons.notifications_outlined,
    'account_circle': Icons.account_circle,
    'arrow_back': Icons.arrow_back,
    'arrow_forward': Icons.arrow_forward,
    'arrow_upward': Icons.arrow_upward,
    'arrow_downward': Icons.arrow_downward,
    'keyboard_arrow_left': Icons.keyboard_arrow_left,
    'keyboard_arrow_right': Icons.keyboard_arrow_right,
    'keyboard_arrow_up': Icons.keyboard_arrow_up,
    'keyboard_arrow_down': Icons.keyboard_arrow_down,
    'expand_more': Icons.expand_more,
    'expand_less': Icons.expand_less,
    'chevron_right': Icons.chevron_right,
    'chevron_left': Icons.chevron_left,
    'lock': Icons.lock,
    'lock_outline': Icons.lock_outline,
    'lock_open': Icons.lock_open,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
    'refresh': Icons.refresh,
    'sync': Icons.sync,
    'download': Icons.download,
    'upload': Icons.upload,
    'attach_file': Icons.attach_file,
    'link': Icons.link,
    'copy': Icons.copy,
    'paste': Icons.paste,
    'cut': Icons.cut,
    'undo': Icons.undo,
    'redo': Icons.redo,
    'filter_list': Icons.filter_list,
    'sort': Icons.sort,
    'play_arrow': Icons.play_arrow,
    'pause': Icons.pause,
    'stop': Icons.stop,
    'skip_next': Icons.skip_next,
    'skip_previous': Icons.skip_previous,
    'volume_up': Icons.volume_up,
    'volume_off': Icons.volume_off,
    'volume_mute': Icons.volume_mute,
    'brightness_6': Icons.brightness_6,
    'dark_mode': Icons.dark_mode,
    'light_mode': Icons.light_mode,
    'wifi': Icons.wifi,
    'wifi_off': Icons.wifi_off,
    'bluetooth': Icons.bluetooth,
    'battery_full': Icons.battery_full,
    'location_on': Icons.location_on,
    'location_off': Icons.location_off,
    'map': Icons.map,
    'shopping_cart': Icons.shopping_cart,
    'payment': Icons.payment,
    'receipt': Icons.receipt,
    'thumb_up': Icons.thumb_up,
    'thumb_down': Icons.thumb_down,
    'comment': Icons.comment,
    'chat': Icons.chat,
    'forum': Icons.forum,
    'calendar_today': Icons.calendar_today,
    'event': Icons.event,
    'access_time': Icons.access_time,
    'timer': Icons.timer,
    'alarm': Icons.alarm,
    'build': Icons.build,
    'code': Icons.code,
    'terminal': Icons.terminal,
    'bug_report': Icons.bug_report,
    'cloud': Icons.cloud,
    'cloud_upload': Icons.cloud_upload,
    'cloud_download': Icons.cloud_download,
    'folder': Icons.folder,
    'folder_open': Icons.folder_open,
    'file_copy': Icons.file_copy,
    'description': Icons.description,
    'article': Icons.article,
    'dashboard': Icons.dashboard,
    'analytics': Icons.analytics,
    'bar_chart': Icons.bar_chart,
    'pie_chart': Icons.pie_chart,
    'trending_up': Icons.trending_up,
    'trending_down': Icons.trending_down,
    'monetization_on': Icons.monetization_on,
    'account_balance': Icons.account_balance,
    'credit_card': Icons.credit_card,
    'local_offer': Icons.local_offer,
    'sell': Icons.sell,
    'storefront': Icons.storefront,
    'inventory': Icons.inventory,
    'category': Icons.category,
    'label': Icons.label,
    'tag': Icons.tag,
    'bookmark': Icons.bookmark,
    'bookmark_border': Icons.bookmark_border,
    'flag': Icons.flag,
    'help': Icons.help,
    'help_outline': Icons.help_outline,
    'support': Icons.support,
    'feedback': Icons.feedback,
    'rate_review': Icons.rate_review,
    'widgets': Icons.widgets,
    'widgets_outlined': Icons.widgets_outlined,
    'extension': Icons.extension,
    'palette': Icons.palette,
    'format_paint': Icons.format_paint,
    'style': Icons.style,
    'text_fields': Icons.text_fields,
    'format_bold': Icons.format_bold,
    'format_italic': Icons.format_italic,
    'format_underline': Icons.format_underlined,
    'format_list_bulleted': Icons.format_list_bulleted,
    'format_list_numbered': Icons.format_list_numbered,
    'table_chart': Icons.table_chart,
    'grid_view': Icons.grid_view,
    'list': Icons.list,
    'view_list': Icons.view_list,
    'view_module': Icons.view_module,
    'view_stream': Icons.view_stream,
    'fullscreen': Icons.fullscreen,
    'fullscreen_exit': Icons.fullscreen_exit,
    'zoom_in': Icons.zoom_in,
    'zoom_out': Icons.zoom_out,
    'crop': Icons.crop,
    'rotate_left': Icons.rotate_left,
    'rotate_right': Icons.rotate_right,
    'flip': Icons.flip,
    'filter': Icons.filter,
    'tune': Icons.tune,
    'wb_sunny': Icons.wb_sunny,
    'nights_stay': Icons.nights_stay,
    'cloud_queue': Icons.cloud_queue,
    'opacity': Icons.opacity,
    'colorize': Icons.colorize,
  };
  return m[name] ?? Icons.widgets_outlined;
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
