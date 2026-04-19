import 'package:flutter/material.dart';

import '../models/widget_node.dart';

// ── Public widget ─────────────────────────────────────────────────────────────

/// Renders a [WidgetNode] tree using Flutter's own widget constructors.
/// No external packages — pixel-perfect real Flutter appearance.
class RfwRenderer extends StatelessWidget {
  final WidgetNode root;
  const RfwRenderer({super.key, required this.root});

  @override
  Widget build(BuildContext context) => _build(root, context);
}

// ── Core recursive builder ────────────────────────────────────────────────────

Widget _build(WidgetNode node, BuildContext context) {
  try {
    return _widget(node, context);
  } catch (e) {
    return _errorBox(node.type, '$e');
  }
}

// ignore: long-method
Widget _widget(WidgetNode node, BuildContext context) {
  final p = node.properties;
  final unslotted =
      node.children.where((c) => !c.properties.containsKey('_slot')).toList();

  Widget? child() =>
      unslotted.isEmpty ? null : _build(unslotted.first, context);
  List<Widget> kids() =>
      unslotted.map((n) => _build(n, context)).toList();

  Widget? slot(String s) {
    for (final c in node.children) {
      if (c.properties['_slot'] == s) return _build(c, context);
    }
    return null;
  }

  List<Widget> slotList(String s) => node.children
      .where((c) => c.properties['_slot'] == s)
      .map((n) => _build(n, context))
      .toList();

  switch (node.type) {
    // ── Text / Icon / Image ──────────────────────────────────────────────────
    case 'Text':
      return Text(
        _str(p, 'text') ?? _str(p, 'data') ?? '',
        style: _textStyle(p),
        textAlign: _textAlign(p, 'textAlign'),
        maxLines: _int(p, 'maxLines'),
        overflow: _textOverflow(p, 'overflow'),
      );

    case 'SelectableText':
      return SelectableText(
        _str(p, 'text') ?? _str(p, 'data') ?? '',
        style: _textStyle(p),
      );

    case 'RichText':
      return RichText(
        text: TextSpan(
          text: _str(p, 'text') ?? '',
          style: DefaultTextStyle.of(context).style,
        ),
      );

    case 'Icon':
      return Icon(
        _icon(p, 'icon') ?? _icon(p, 'data') ?? Icons.widgets_outlined,
        size: _double(p, 'size'),
        color: _color(p, 'color'),
      );

    case 'Image':
    case 'Image.network':
    case 'Image.asset':
    case 'Image.file':
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: _double(p, 'width') ?? 120,
          height: _double(p, 'height') ?? 80,
          color: Colors.grey.shade200,
          child: const Center(
              child: Icon(Icons.image_outlined, color: Colors.grey, size: 32)),
        ),
      );

    // ── Layout ───────────────────────────────────────────────────────────────
    case 'Container':
      return Container(
        width: _double(p, 'width'),
        height: _double(p, 'height'),
        color: p.containsKey('decoration') ? null : _color(p, 'color'),
        padding: _edgeInsets(p, 'padding'),
        margin: _edgeInsets(p, 'margin'),
        alignment: _alignment(p, 'alignment'),
        child: child(),
      );

    case 'Row':
      return Row(
        mainAxisAlignment:
            _mainAxisAlignment(p, 'mainAxisAlignment') ?? MainAxisAlignment.start,
        crossAxisAlignment:
            _crossAxisAlignment(p, 'crossAxisAlignment') ?? CrossAxisAlignment.center,
        mainAxisSize: _mainAxisSize(p, 'mainAxisSize') ?? MainAxisSize.max,
        children: kids(),
      );

    case 'Column':
      return Column(
        mainAxisAlignment:
            _mainAxisAlignment(p, 'mainAxisAlignment') ?? MainAxisAlignment.start,
        crossAxisAlignment:
            _crossAxisAlignment(p, 'crossAxisAlignment') ?? CrossAxisAlignment.center,
        mainAxisSize: _mainAxisSize(p, 'mainAxisSize') ?? MainAxisSize.max,
        children: kids(),
      );

    case 'Stack':
      return Stack(
        alignment: _alignment(p, 'alignment') ?? Alignment.topLeft,
        fit: _stackFit(p, 'fit') ?? StackFit.loose,
        children: kids(),
      );

    case 'Wrap':
      return Wrap(
        spacing: _double(p, 'spacing') ?? 0,
        runSpacing: _double(p, 'runSpacing') ?? 0,
        direction: _axis(p, 'direction') ?? Axis.horizontal,
        alignment: _wrapAlignment(p, 'alignment') ?? WrapAlignment.start,
        children: kids(),
      );

    case 'Expanded':
      return Expanded(
        flex: _int(p, 'flex') ?? 1,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'Flexible':
      return Flexible(
        flex: _int(p, 'flex') ?? 1,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'Spacer':
      return Spacer(flex: _int(p, 'flex') ?? 1);

    case 'SizedBox':
      final w = _double(p, 'width');
      final h = _double(p, 'height');
      if (w == null && h == null && unslotted.isEmpty) {
        return const SizedBox.shrink();
      }
      return SizedBox(width: w, height: h, child: child());

    case 'Padding':
      return Padding(
        padding: _edgeInsets(p, 'padding') ?? const EdgeInsets.all(8),
        child: child(),
      );

    case 'Center':
      return Center(child: child());

    case 'Align':
      return Align(
        alignment: _alignment(p, 'alignment') ?? Alignment.center,
        child: child(),
      );

    case 'Positioned':
      return Positioned(
        left: _double(p, 'left'),
        top: _double(p, 'top'),
        right: _double(p, 'right'),
        bottom: _double(p, 'bottom'),
        width: _double(p, 'width'),
        height: _double(p, 'height'),
        child: child() ?? const SizedBox.shrink(),
      );

    case 'AspectRatio':
      return AspectRatio(
        aspectRatio: _double(p, 'aspectRatio') ?? 1.0,
        child: child(),
      );

    case 'FittedBox':
      return FittedBox(
        fit: _boxFit(p, 'fit') ?? BoxFit.contain,
        child: child(),
      );

    case 'ClipRRect':
      return ClipRRect(
        borderRadius:
            BorderRadius.circular(_double(p, 'borderRadius') ?? 0),
        child: child(),
      );

    case 'ClipOval':
      return ClipOval(child: child());

    case 'ClipRect':
    case 'ClipPath':
      return ClipRect(child: child());

    case 'ColoredBox':
      return ColoredBox(
        color: _color(p, 'color') ?? Colors.grey.shade200,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'DecoratedBox':
      return DecoratedBox(
        decoration: BoxDecoration(
          color: _color(p, 'color'),
          borderRadius: _double(p, 'borderRadius') != null
              ? BorderRadius.circular(_double(p, 'borderRadius')!)
              : null,
        ),
        child: child(),
      );

    case 'FractionallySizedBox':
      return FractionallySizedBox(
        widthFactor: _double(p, 'widthFactor'),
        heightFactor: _double(p, 'heightFactor'),
        child: child(),
      );

    case 'LimitedBox':
      return LimitedBox(
        maxWidth: _double(p, 'maxWidth') ?? double.infinity,
        maxHeight: _double(p, 'maxHeight') ?? double.infinity,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'OverflowBox':
      return OverflowBox(
        maxWidth: _double(p, 'maxWidth'),
        maxHeight: _double(p, 'maxHeight'),
        child: child() ?? const SizedBox.shrink(),
      );

    case 'RotatedBox':
      return RotatedBox(
        quarterTurns: _int(p, 'quarterTurns') ?? 0,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'Transform':
      return Transform.scale(
        scale: _double(p, 'scale') ?? 1.0,
        child: child(),
      );

    case 'Opacity':
      return Opacity(
        opacity: (_double(p, 'opacity') ?? 1.0).clamp(0.0, 1.0),
        child: child(),
      );

    case 'ConstrainedBox':
      return ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: _double(p, 'minWidth') ?? 0,
          minHeight: _double(p, 'minHeight') ?? 0,
          maxWidth: _double(p, 'maxWidth') ?? double.infinity,
          maxHeight: _double(p, 'maxHeight') ?? double.infinity,
        ),
        child: child(),
      );

    case 'IntrinsicWidth':
      return IntrinsicWidth(child: child());

    case 'IntrinsicHeight':
      return IntrinsicHeight(child: child());

    case 'PhysicalModel':
      return PhysicalModel(
        color: _color(p, 'color') ?? Colors.white,
        elevation: _double(p, 'elevation') ?? 4.0,
        borderRadius:
            BorderRadius.circular(_double(p, 'borderRadius') ?? 0),
        child: child() ?? const SizedBox.shrink(),
      );

    case 'SafeArea':
      return SafeArea(child: child() ?? const SizedBox.shrink());

    case 'Material':
      return Material(
        color: _color(p, 'color'),
        elevation: _double(p, 'elevation') ?? 0,
        child: child(),
      );

    // ── Scroll ────────────────────────────────────────────────────────────────
    case 'SingleChildScrollView':
      return SingleChildScrollView(
        scrollDirection: _axis(p, 'scrollDirection') ?? Axis.vertical,
        child: child(),
      );

    case 'ListView':
      return ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: kids(),
      );

    case 'GridView':
      return GridView.count(
        crossAxisCount: _int(p, 'crossAxisCount') ?? 2,
        crossAxisSpacing: _double(p, 'crossAxisSpacing') ?? 0,
        mainAxisSpacing: _double(p, 'mainAxisSpacing') ?? 0,
        childAspectRatio: _double(p, 'childAspectRatio') ?? 1.0,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: kids(),
      );

    case 'CustomScrollView':
      return CustomScrollView(
        shrinkWrap: true,
        slivers: kids(),
      );

    case 'ReorderableListView':
      return ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        onReorder: (_, __) {},
        children: unslotted
            .asMap()
            .entries
            .map((e) => KeyedSubtree(
                  key: ValueKey(e.key),
                  child: _build(e.value, context),
                ))
            .toList(),
      );

    case 'PageView':
      return SizedBox(
        height: 200,
        child: PageView(
          physics: const NeverScrollableScrollPhysics(),
          children:
              unslotted.isEmpty ? [const SizedBox.shrink()] : kids(),
        ),
      );

    case 'RefreshIndicator':
      return RefreshIndicator(
        onRefresh: () async {},
        child: child() ?? const SizedBox.shrink(),
      );

    case 'InteractiveViewer':
      return InteractiveViewer(
          child: child() ?? const SizedBox.shrink());

    case 'Dismissible':
      return Dismissible(
        key: UniqueKey(),
        child: child() ?? const SizedBox.shrink(),
      );

    // ── Sliver ────────────────────────────────────────────────────────────────
    case 'SliverAppBar':
      return SliverAppBar(
        title: _str(p, 'title') != null ? Text(_str(p, 'title')!) : null,
        floating: _bool(p, 'floating') ?? false,
        pinned: _bool(p, 'pinned') ?? false,
      );

    case 'SliverList':
    case 'SliverGrid':
    case 'SliverToBoxAdapter':
      return SliverToBoxAdapter(child: child());

    case 'SliverFillRemaining':
      return SliverFillRemaining(child: child());

    // ── Scaffold ──────────────────────────────────────────────────────────────
    case 'Scaffold':
      return Scaffold(
        appBar: slot('appBar') as PreferredSizeWidget?,
        body: slot('body') ?? child(),
        floatingActionButton: slot('floatingActionButton'),
        drawer: slot('drawer'),
        bottomNavigationBar: slot('bottomNavigationBar'),
        backgroundColor: _color(p, 'backgroundColor'),
      );

    case 'AppBar':
      final actions = slotList('actions');
      return AppBar(
        title: slot('title') ??
            (_str(p, 'title') != null ? Text(_str(p, 'title')!) : null),
        backgroundColor: _color(p, 'backgroundColor'),
        foregroundColor: _color(p, 'foregroundColor'),
        centerTitle: _bool(p, 'centerTitle'),
        elevation: _double(p, 'elevation'),
        leading: slot('leading'),
        actions: actions.isEmpty ? null : actions,
      );

    case 'BottomNavigationBar':
      return BottomNavigationBar(
        currentIndex: _int(p, 'currentIndex') ?? 0,
        onTap: (_) {},
        items: unslotted.isEmpty
            ? const [
                BottomNavigationBarItem(
                    icon: Icon(Icons.home), label: 'Home'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.search), label: 'Search'),
                BottomNavigationBarItem(
                    icon: Icon(Icons.person), label: 'Profile'),
              ]
            : unslotted
                .map((n) => BottomNavigationBarItem(
                      icon: Icon(_icon(n.properties, 'icon') ?? Icons.circle),
                      label: _str(n.properties, 'label') ?? 'Item',
                    ))
                .toList(),
      );

    case 'NavigationBar':
      return NavigationBar(
        selectedIndex: _int(p, 'selectedIndex') ?? 0,
        onDestinationSelected: (_) {},
        destinations: unslotted.isEmpty
            ? const [
                NavigationDestination(
                    icon: Icon(Icons.home_outlined), label: 'Home'),
                NavigationDestination(
                    icon: Icon(Icons.search), label: 'Search'),
                NavigationDestination(
                    icon: Icon(Icons.person_outline), label: 'Profile'),
              ]
            : unslotted
                .map((n) => NavigationDestination(
                      icon: Icon(_icon(n.properties, 'icon') ?? Icons.circle),
                      label: _str(n.properties, 'label') ?? 'Item',
                    ))
                .toList(),
      );

    case 'NavigationRail':
      return NavigationRail(
        selectedIndex: _int(p, 'selectedIndex') ?? 0,
        onDestinationSelected: (_) {},
        labelType: NavigationRailLabelType.all,
        destinations: const [
          NavigationRailDestination(
              icon: Icon(Icons.home_outlined), label: Text('Home')),
          NavigationRailDestination(
              icon: Icon(Icons.search), label: Text('Search')),
          NavigationRailDestination(
              icon: Icon(Icons.settings_outlined), label: Text('Settings')),
        ],
      );

    case 'Drawer':
      return Drawer(child: child());

    case 'DrawerHeader':
      return DrawerHeader(
        decoration:
            BoxDecoration(color: _color(p, 'color') ?? Colors.blue),
        child: Text(
          _str(p, 'title') ?? 'Header',
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      );

    // ── Tab ───────────────────────────────────────────────────────────────────
    case 'DefaultTabController':
      return DefaultTabController(
        length: _int(p, 'length') ?? 2,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'TabBar':
      return Material(
        color: Theme.of(context).colorScheme.primary,
        child: TabBar(
          tabs: unslotted.isEmpty
              ? const [Tab(text: 'Tab 1'), Tab(text: 'Tab 2')]
              : kids().map((w) => Tab(child: w)).toList(),
          labelColor: Colors.white,
          indicatorColor: Colors.white,
        ),
      );

    case 'Tab':
      return Tab(
        text: _str(p, 'text'),
        icon: _icon(p, 'icon') != null ? Icon(_icon(p, 'icon')) : null,
      );

    case 'TabBarView':
      return SizedBox(
        height: 200,
        child: TabBarView(
          physics: const NeverScrollableScrollPhysics(),
          children: unslotted.isEmpty ? [const SizedBox.shrink()] : kids(),
        ),
      );

    // ── Card / List tiles ─────────────────────────────────────────────────────
    case 'Card':
      return Card(
        elevation: _double(p, 'elevation') ?? 1,
        color: _color(p, 'color'),
        child: child(),
      );

    case 'ListTile':
      return ListTile(
        title: slot('title') ??
            (_str(p, 'title') != null ? Text(_str(p, 'title')!) : null),
        subtitle: slot('subtitle') ??
            (_str(p, 'subtitle') != null ? Text(_str(p, 'subtitle')!) : null),
        leading: slot('leading'),
        trailing: slot('trailing'),
        dense: _bool(p, 'dense'),
      );

    case 'Divider':
      return Divider(
        height: _double(p, 'height'),
        thickness: _double(p, 'thickness'),
        color: _color(p, 'color'),
      );

    case 'VerticalDivider':
      return VerticalDivider(
        width: _double(p, 'width'),
        thickness: _double(p, 'thickness'),
        color: _color(p, 'color'),
      );

    case 'ExpansionTile':
      return ExpansionTile(
        title: Text(_str(p, 'title') ?? 'Expansion Tile'),
        initiallyExpanded: _bool(p, 'initiallyExpanded') ?? false,
        children: kids(),
      );

    // ── Buttons ───────────────────────────────────────────────────────────────
    case 'ElevatedButton':
      return ElevatedButton(
        onPressed: null,
        style: _color(p, 'backgroundColor') != null
            ? ElevatedButton.styleFrom(
                backgroundColor: _color(p, 'backgroundColor'))
            : null,
        child: slot('child') ??
            child() ??
            Text(_str(p, 'text') ?? 'Button'),
      );

    case 'TextButton':
      return TextButton(
        onPressed: null,
        child: slot('child') ??
            child() ??
            Text(_str(p, 'text') ?? 'Button'),
      );

    case 'OutlinedButton':
      return OutlinedButton(
        onPressed: null,
        child: slot('child') ??
            child() ??
            Text(_str(p, 'text') ?? 'Button'),
      );

    case 'FilledButton':
      return FilledButton(
        onPressed: null,
        child: slot('child') ??
            child() ??
            Text(_str(p, 'text') ?? 'Button'),
      );

    case 'IconButton':
      return IconButton(
        onPressed: null,
        icon: slot('icon') ??
            child() ??
            Icon(_icon(p, 'icon') ?? Icons.touch_app),
        tooltip: _str(p, 'tooltip'),
      );

    case 'FloatingActionButton':
      return FloatingActionButton(
        onPressed: null,
        backgroundColor: _color(p, 'backgroundColor'),
        child: slot('child') ??
            child() ??
            Icon(_icon(p, 'icon') ?? Icons.add),
      );

    case 'FloatingActionButton.extended':
      return FloatingActionButton.extended(
        onPressed: null,
        label: Text(_str(p, 'label') ?? 'Action'),
        icon: _icon(p, 'icon') != null ? Icon(_icon(p, 'icon')) : null,
      );

    case 'FloatingActionButton.small':
      return FloatingActionButton.small(
        onPressed: null,
        child: Icon(_icon(p, 'icon') ?? Icons.add),
      );

    case 'FloatingActionButton.large':
      return FloatingActionButton.large(
        onPressed: null,
        child: Icon(_icon(p, 'icon') ?? Icons.add),
      );

    case 'ToggleButtons':
      return IgnorePointer(
        child: ToggleButtons(
          isSelected: const [true, false, false],
          onPressed: (_) {},
          children: kids().isEmpty
              ? const [
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('A')),
                  Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('B')),
                ]
              : kids(),
        ),
      );

    case 'SegmentedButton':
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

    case 'PopupMenuButton':
      return IconButton(
          icon: const Icon(Icons.more_vert), onPressed: null);

    // ── Input ─────────────────────────────────────────────────────────────────
    case 'TextField':
      return IgnorePointer(
        child: TextField(
          enabled: false,
          decoration: InputDecoration(
            hintText: _str(p, 'hintText'),
            labelText: _str(p, 'labelText'),
            border: const OutlineInputBorder(),
          ),
        ),
      );

    case 'TextFormField':
      return IgnorePointer(
        child: TextFormField(
          enabled: false,
          decoration: InputDecoration(
            hintText: _str(p, 'hintText'),
            labelText: _str(p, 'labelText'),
            border: const OutlineInputBorder(),
          ),
        ),
      );

    case 'Form':
      return child() ?? const SizedBox.shrink();

    case 'Checkbox':
      return IgnorePointer(
        child: Checkbox(
          value: _bool(p, 'value') ?? false,
          onChanged: (_) {},
        ),
      );

    case 'Switch':
      return IgnorePointer(
        child: Switch(
          value: _bool(p, 'value') ?? false,
          onChanged: (_) {},
        ),
      );

    case 'Slider':
      return IgnorePointer(
        child: Slider(
          value: (_double(p, 'value') ?? 0.5).clamp(
              _double(p, 'min') ?? 0, _double(p, 'max') ?? 1),
          min: _double(p, 'min') ?? 0,
          max: _double(p, 'max') ?? 1,
          onChanged: (_) {},
        ),
      );

    case 'RangeSlider':
      return IgnorePointer(
        child: RangeSlider(
          values: const RangeValues(0.2, 0.8),
          onChanged: null,
        ),
      );

    case 'Radio':
      return IgnorePointer(
        child: Radio<int>(value: 0, groupValue: 0, onChanged: null),
      );

    case 'RadioListTile':
      return RadioListTile<int>(
        value: 0,
        groupValue: 0,
        onChanged: null,
        title: Text(_str(p, 'title') ?? 'Option'),
      );

    case 'CheckboxListTile':
      return CheckboxListTile(
        value: _bool(p, 'value') ?? false,
        onChanged: null,
        title: Text(_str(p, 'title') ?? 'Checkbox'),
      );

    case 'SwitchListTile':
      return SwitchListTile(
        value: _bool(p, 'value') ?? false,
        onChanged: null,
        title: Text(_str(p, 'title') ?? 'Switch'),
      );

    case 'DropdownButton':
    case 'DropdownMenu':
      return IgnorePointer(
        child: InputDecorator(
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            isDense: true,
            labelText: _str(p, 'label') ??
                _str(p, 'hintText') ??
                _str(p, 'hint') ??
                'Select...',
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

    case 'SearchBar':
      return const IgnorePointer(
        child: SearchBar(
          leading: Icon(Icons.search),
          hintText: 'Search...',
        ),
      );

    // ── Feedback ──────────────────────────────────────────────────────────────
    case 'CircularProgressIndicator':
      return Center(
        child: SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            value: _double(p, 'value'),
            color: _color(p, 'color'),
          ),
        ),
      );

    case 'LinearProgressIndicator':
      return LinearProgressIndicator(
        value: _double(p, 'value'),
        color: _color(p, 'color'),
        backgroundColor: _color(p, 'backgroundColor'),
      );

    case 'AlertDialog':
      final dialogActions = slotList('actions');
      return AlertDialog(
        title: _str(p, 'title') != null ? Text(_str(p, 'title')!) : null,
        content: child() ??
            (_str(p, 'content') != null
                ? Text(_str(p, 'content')!)
                : null),
        actions: dialogActions.isEmpty ? null : dialogActions,
      );

    case 'Dialog':
      return Dialog(child: child());

    case 'SnackBar':
      return Material(
        color: Colors.grey.shade800,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            _str(p, 'content') ?? 'Snackbar',
            style: const TextStyle(color: Colors.white),
          ),
        ),
      );

    case 'BottomSheet':
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: child(),
      );

    // ── Chips ─────────────────────────────────────────────────────────────────
    case 'Chip':
      return Chip(label: Text(_str(p, 'label') ?? 'Chip'));

    case 'InputChip':
      return InputChip(
        label: Text(_str(p, 'label') ?? 'Input'),
        onDeleted: () {},
      );

    case 'FilterChip':
      return FilterChip(
        label: Text(_str(p, 'label') ?? 'Filter'),
        selected: _bool(p, 'selected') ?? false,
        onSelected: (_) {},
      );

    case 'ActionChip':
      return ActionChip(
        label: Text(_str(p, 'label') ?? 'Action'),
        onPressed: () {},
      );

    case 'ChoiceChip':
      return ChoiceChip(
        label: Text(_str(p, 'label') ?? 'Choice'),
        selected: _bool(p, 'selected') ?? false,
        onSelected: (_) {},
      );

    // ── Animation ─────────────────────────────────────────────────────────────
    case 'AnimatedContainer':
      return AnimatedContainer(
        duration:
            Duration(milliseconds: _int(p, 'duration') ?? 300),
        width: _double(p, 'width'),
        height: _double(p, 'height'),
        color: _color(p, 'color'),
        child: child(),
      );

    case 'AnimatedOpacity':
      return AnimatedOpacity(
        opacity: (_double(p, 'opacity') ?? 1.0).clamp(0.0, 1.0),
        duration: const Duration(milliseconds: 300),
        child: child(),
      );

    case 'AnimatedPadding':
      return AnimatedPadding(
        padding: _edgeInsets(p, 'padding') ?? const EdgeInsets.all(8),
        duration: const Duration(milliseconds: 300),
        child: child(),
      );

    case 'AnimatedAlign':
      return AnimatedAlign(
        alignment: _alignment(p, 'alignment') ?? Alignment.center,
        duration: const Duration(milliseconds: 300),
        child: child(),
      );

    case 'AnimatedScale':
      return AnimatedScale(
        scale: _double(p, 'scale') ?? 1.0,
        duration: const Duration(milliseconds: 300),
        child: child(),
      );

    case 'AnimatedSwitcher':
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: child() ?? const SizedBox.shrink(),
      );

    case 'AnimatedCrossFade':
      return AnimatedCrossFade(
        firstChild: unslotted.isNotEmpty
            ? _build(unslotted.first, context)
            : const SizedBox.shrink(),
        secondChild: unslotted.length > 1
            ? _build(unslotted[1], context)
            : const SizedBox.shrink(),
        crossFadeState: CrossFadeState.showFirst,
        duration: const Duration(milliseconds: 300),
      );

    // ── Misc ──────────────────────────────────────────────────────────────────
    case 'Tooltip':
      return Tooltip(
          message: _str(p, 'message') ?? '', child: child());

    case 'Hero':
      return Hero(
        tag: _str(p, 'tag') ?? 'hero_${node.id}',
        child: child() ?? const SizedBox.shrink(),
      );

    case 'Badge':
      return Badge(
        label: _str(p, 'label') != null ? Text(_str(p, 'label')!) : null,
        child: child(),
      );

    case 'DefaultTextStyle':
      return DefaultTextStyle(
        style:
            _textStyle(p) ?? DefaultTextStyle.of(context).style,
        child: child() ?? const SizedBox.shrink(),
      );

    case 'Theme':
      return Theme(
          data: Theme.of(context),
          child: child() ?? const SizedBox.shrink());

    case 'InkWell':
    case 'InkResponse':
    case 'GestureDetector':
    case 'Listener':
      return child() ?? const SizedBox.shrink();

    case 'AbsorbPointer':
    case 'IgnorePointer':
      return IgnorePointer(child: child());

    case 'Builder':
    case 'LayoutBuilder':
    case 'RepaintBoundary':
    case 'NotificationListener':
    case 'MediaQuery':
    case 'Directionality':
      return child() ?? const SizedBox.shrink();

    case 'FutureBuilder':
    case 'StreamBuilder':
    case 'ValueListenableBuilder':
      return child() ?? _placeholder(node.type);

    default:
      return _placeholder(node.type);
  }
}

// ── Property helpers ──────────────────────────────────────────────────────────

String? _str(Map<String, dynamic> p, String key) {
  final v = p[key];
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  if ((s.startsWith("'") && s.endsWith("'")) ||
      (s.startsWith('"') && s.endsWith('"'))) {
    return s.substring(1, s.length - 1);
  }
  return s;
}

double? _double(Map<String, dynamic> p, String key) =>
    p[key] != null ? double.tryParse(p[key].toString()) : null;

int? _int(Map<String, dynamic> p, String key) {
  final v = p[key];
  if (v == null) return null;
  return int.tryParse(v.toString()) ??
      double.tryParse(v.toString())?.toInt();
}

bool? _bool(Map<String, dynamic> p, String key) {
  final v = p[key];
  if (v == null) return null;
  if (v is bool) return v;
  return v.toString() == 'true';
}

// ── Color ─────────────────────────────────────────────────────────────────────

Color? _color(Map<String, dynamic> p, String key) {
  final v = p[key]?.toString().trim();
  if (v == null || v.isEmpty) return null;
  if (v.startsWith('Colors.')) {
    final name = v.substring(7).split('.').first;
    return _colorByName[name];
  }
  final hex = RegExp(r'0x([0-9A-Fa-f]{8})').firstMatch(v);
  if (hex != null) {
    return Color(int.parse(hex.group(1)!, radix: 16));
  }
  return null;
}

const _colorByName = <String, Color>{
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

// ── TextStyle ─────────────────────────────────────────────────────────────────

TextStyle? _textStyle(Map<String, dynamic> p) {
  final size = _double(p, 'fontSize');
  final col = _color(p, 'color');
  final fw = _fontWeight(p['fontWeight']?.toString());
  if (size == null && col == null && fw == null) return null;
  return TextStyle(fontSize: size, color: col, fontWeight: fw);
}

FontWeight? _fontWeight(String? v) {
  if (v == null) return null;
  final name = v.contains('.') ? v.split('.').last : v;
  return const {
    'bold': FontWeight.bold,
    'normal': FontWeight.normal,
    'w100': FontWeight.w100,
    'w200': FontWeight.w200,
    'w300': FontWeight.w300,
    'w400': FontWeight.w400,
    'w500': FontWeight.w500,
    'w600': FontWeight.w600,
    'w700': FontWeight.w700,
    'w800': FontWeight.w800,
    'w900': FontWeight.w900,
  }[name];
}

// ── Enum helpers ──────────────────────────────────────────────────────────────

String? _enumLast(Map<String, dynamic> p, String key) {
  final v = p[key]?.toString();
  if (v == null) return null;
  return v.contains('.') ? v.split('.').last : v;
}

TextAlign? _textAlign(Map<String, dynamic> p, String key) =>
    const {
      'left': TextAlign.left,
      'right': TextAlign.right,
      'center': TextAlign.center,
      'justify': TextAlign.justify,
      'start': TextAlign.start,
      'end': TextAlign.end,
    }[_enumLast(p, key)];

TextOverflow? _textOverflow(Map<String, dynamic> p, String key) =>
    const {
      'clip': TextOverflow.clip,
      'ellipsis': TextOverflow.ellipsis,
      'fade': TextOverflow.fade,
      'visible': TextOverflow.visible,
    }[_enumLast(p, key)];

Axis? _axis(Map<String, dynamic> p, String key) =>
    const {
      'horizontal': Axis.horizontal,
      'vertical': Axis.vertical,
    }[_enumLast(p, key)];

BoxFit? _boxFit(Map<String, dynamic> p, String key) =>
    const {
      'fill': BoxFit.fill,
      'contain': BoxFit.contain,
      'cover': BoxFit.cover,
      'fitWidth': BoxFit.fitWidth,
      'fitHeight': BoxFit.fitHeight,
      'none': BoxFit.none,
      'scaleDown': BoxFit.scaleDown,
    }[_enumLast(p, key)];

StackFit? _stackFit(Map<String, dynamic> p, String key) =>
    const {
      'loose': StackFit.loose,
      'expand': StackFit.expand,
      'passthrough': StackFit.passthrough,
    }[_enumLast(p, key)];

MainAxisAlignment? _mainAxisAlignment(Map<String, dynamic> p, String key) =>
    const {
      'start': MainAxisAlignment.start,
      'end': MainAxisAlignment.end,
      'center': MainAxisAlignment.center,
      'spaceBetween': MainAxisAlignment.spaceBetween,
      'spaceAround': MainAxisAlignment.spaceAround,
      'spaceEvenly': MainAxisAlignment.spaceEvenly,
    }[_enumLast(p, key)];

CrossAxisAlignment? _crossAxisAlignment(
        Map<String, dynamic> p, String key) =>
    const {
      'start': CrossAxisAlignment.start,
      'end': CrossAxisAlignment.end,
      'center': CrossAxisAlignment.center,
      'stretch': CrossAxisAlignment.stretch,
      'baseline': CrossAxisAlignment.baseline,
    }[_enumLast(p, key)];

MainAxisSize? _mainAxisSize(Map<String, dynamic> p, String key) =>
    const {
      'min': MainAxisSize.min,
      'max': MainAxisSize.max,
    }[_enumLast(p, key)];

WrapAlignment? _wrapAlignment(Map<String, dynamic> p, String key) =>
    const {
      'start': WrapAlignment.start,
      'end': WrapAlignment.end,
      'center': WrapAlignment.center,
      'spaceBetween': WrapAlignment.spaceBetween,
      'spaceAround': WrapAlignment.spaceAround,
      'spaceEvenly': WrapAlignment.spaceEvenly,
    }[_enumLast(p, key)];

Alignment? _alignment(Map<String, dynamic> p, String key) =>
    const {
      'topLeft': Alignment.topLeft,
      'topCenter': Alignment.topCenter,
      'topRight': Alignment.topRight,
      'centerLeft': Alignment.centerLeft,
      'center': Alignment.center,
      'centerRight': Alignment.centerRight,
      'bottomLeft': Alignment.bottomLeft,
      'bottomCenter': Alignment.bottomCenter,
      'bottomRight': Alignment.bottomRight,
    }[_enumLast(p, key)];

// ── EdgeInsets ────────────────────────────────────────────────────────────────

EdgeInsets? _edgeInsets(Map<String, dynamic> p, String key) {
  final v = p[key]?.toString().trim();
  if (v == null || v.isEmpty) return null;

  final allM =
      RegExp(r'EdgeInsets\.all\(\s*([0-9.]+)\s*\)').firstMatch(v);
  if (allM != null) return EdgeInsets.all(double.parse(allM.group(1)!));

  final symM = RegExp(r'EdgeInsets\.symmetric\(([^)]+)\)').firstMatch(v);
  if (symM != null) {
    final a = symM.group(1)!;
    final h =
        RegExp(r'horizontal:\s*([0-9.]+)').firstMatch(a)?.group(1);
    final vert =
        RegExp(r'vertical:\s*([0-9.]+)').firstMatch(a)?.group(1);
    return EdgeInsets.symmetric(
      horizontal: h != null ? double.parse(h) : 0,
      vertical: vert != null ? double.parse(vert) : 0,
    );
  }

  final onlyM =
      RegExp(r'EdgeInsets\.only\(([^)]+)\)').firstMatch(v);
  if (onlyM != null) {
    final a = onlyM.group(1)!;
    double? g(String n) {
      final m = RegExp('$n:\\s*([0-9.]+)').firstMatch(a);
      return m != null ? double.parse(m.group(1)!) : null;
    }
    return EdgeInsets.only(
      left: g('left') ?? 0,
      top: g('top') ?? 0,
      right: g('right') ?? 0,
      bottom: g('bottom') ?? 0,
    );
  }

  final num = double.tryParse(v);
  if (num != null) return EdgeInsets.all(num);
  return null;
}

// ── Icon ──────────────────────────────────────────────────────────────────────

/// Returns a CONST [IconData] so the tree-shaker stays happy.
/// All values come from the pre-built const lookup table.
IconData? _icon(Map<String, dynamic> p, String key) {
  final v = p[key]?.toString().trim();
  if (v == null || v.isEmpty) return null;
  if (v.startsWith('Icons.')) {
    var name = v.substring(6);
    // Strip variant suffixes
    for (final s in const ['_rounded', '_outlined', '_sharp', '_filled']) {
      name = name.replaceAll(s, '');
    }
    return _iconByName[name] ?? Icons.widgets_outlined;
  }
  return null;
}

// All values are const IconData — no non-const IconData in this file.
const _iconByName = <String, IconData>{
  'add': Icons.add,
  'add_circle': Icons.add_circle,
  'add_circle_outline': Icons.add_circle_outline,
  'remove': Icons.remove,
  'close': Icons.close,
  'check': Icons.check,
  'check_circle': Icons.check_circle,
  'cancel': Icons.cancel,
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
  'delete': Icons.delete,
  'info': Icons.info,
  'info_outline': Icons.info_outline,
  'warning': Icons.warning,
  'error': Icons.error,
  'email': Icons.email,
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
  'chevron_right': Icons.chevron_right,
  'chevron_left': Icons.chevron_left,
  'expand_more': Icons.expand_more,
  'expand_less': Icons.expand_less,
  'lock': Icons.lock,
  'lock_open': Icons.lock_open,
  'visibility': Icons.visibility,
  'visibility_off': Icons.visibility_off,
  'refresh': Icons.refresh,
  'download': Icons.download,
  'upload': Icons.upload,
  'attach_file': Icons.attach_file,
  'link': Icons.link,
  'copy': Icons.copy,
  'filter_list': Icons.filter_list,
  'sort': Icons.sort,
  'play_arrow': Icons.play_arrow,
  'pause': Icons.pause,
  'stop': Icons.stop,
  'volume_up': Icons.volume_up,
  'volume_off': Icons.volume_off,
  'wifi': Icons.wifi,
  'bluetooth': Icons.bluetooth,
  'location_on': Icons.location_on,
  'map': Icons.map,
  'shopping_cart': Icons.shopping_cart,
  'payment': Icons.payment,
  'thumb_up': Icons.thumb_up,
  'thumb_down': Icons.thumb_down,
  'comment': Icons.comment,
  'chat': Icons.chat,
  'calendar_today': Icons.calendar_today,
  'access_time': Icons.access_time,
  'build': Icons.build,
  'code': Icons.code,
  'dashboard': Icons.dashboard,
  'cloud': Icons.cloud,
  'cloud_upload': Icons.cloud_upload,
  'cloud_download': Icons.cloud_download,
  'folder': Icons.folder,
  'folder_open': Icons.folder_open,
  'description': Icons.description,
  'label': Icons.label,
  'bookmark': Icons.bookmark,
  'bookmark_border': Icons.bookmark_border,
  'flag': Icons.flag,
  'help': Icons.help,
  'widgets': Icons.widgets,
  'widgets_outlined': Icons.widgets_outlined,
  'extension': Icons.extension,
  'palette': Icons.palette,
  'format_bold': Icons.format_bold,
  'format_italic': Icons.format_italic,
  'format_underlined': Icons.format_underlined,
  'touch_app': Icons.touch_app,
  'circle': Icons.circle,
  'pending': Icons.pending,
  'stream': Icons.stream,
  'smartphone': Icons.smartphone,
  'tablet': Icons.tablet,
  'computer': Icons.computer,
  'content_copy': Icons.content_copy,
  'content_paste': Icons.content_paste,
  'content_cut': Icons.content_cut,
  'undo': Icons.undo,
  'redo': Icons.redo,
};

// ── Placeholder / error boxes ─────────────────────────────────────────────────

Widget _placeholder(String type) => Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.4)),
        color: Colors.purple.withValues(alpha: 0.06),
      ),
      child: Text(
        type,
        style: const TextStyle(
          fontSize: 11,
          fontFamily: 'monospace',
          color: Colors.purple,
        ),
      ),
    );

Widget _errorBox(String type, String error) => Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red),
        color: Colors.red.shade50,
      ),
      child: Text(
        '$type\n$error',
        style: const TextStyle(fontSize: 10, color: Colors.red),
      ),
    );
