import 'package:flutter/material.dart';

/// Metadata for a single Flutter widget shown in the palette.
class FlutterWidgetDef {
  final String name;
  final String category;
  final IconData icon;
  final Color color;
  final Map<String, dynamic> defaultProperties;

  const FlutterWidgetDef({
    required this.name,
    required this.category,
    required this.icon,
    required this.color,
    this.defaultProperties = const {},
  });
}

/// All available Flutter widgets grouped by category.
const List<FlutterWidgetDef> kFlutterWidgets = [
  // ── Layout ──────────────────────────────────────────────────────────────
  FlutterWidgetDef(
    name: 'Row',
    category: 'Layout',
    icon: Icons.table_rows_outlined,
    color: Color(0xFF1976D2),
  ),
  FlutterWidgetDef(
    name: 'Column',
    category: 'Layout',
    icon: Icons.view_column_outlined,
    color: Color(0xFF1976D2),
  ),
  FlutterWidgetDef(
    name: 'Stack',
    category: 'Layout',
    icon: Icons.layers_outlined,
    color: Color(0xFF1565C0),
  ),
  FlutterWidgetDef(
    name: 'Wrap',
    category: 'Layout',
    icon: Icons.wrap_text_rounded,
    color: Color(0xFF0288D1),
  ),
  FlutterWidgetDef(
    name: 'Container',
    category: 'Layout',
    icon: Icons.crop_square_rounded,
    color: Color(0xFF2196F3),
  ),
  FlutterWidgetDef(
    name: 'Padding',
    category: 'Layout',
    icon: Icons.padding_outlined,
    color: Color(0xFF42A5F5),
  ),
  FlutterWidgetDef(
    name: 'Center',
    category: 'Layout',
    icon: Icons.filter_center_focus_rounded,
    color: Color(0xFF64B5F6),
  ),
  FlutterWidgetDef(
    name: 'Align',
    category: 'Layout',
    icon: Icons.align_horizontal_center_outlined,
    color: Color(0xFF64B5F6),
  ),
  FlutterWidgetDef(
    name: 'Expanded',
    category: 'Layout',
    icon: Icons.unfold_more_rounded,
    color: Color(0xFF0097A7),
  ),
  FlutterWidgetDef(
    name: 'Flexible',
    category: 'Layout',
    icon: Icons.swap_horiz_rounded,
    color: Color(0xFF00ACC1),
  ),
  FlutterWidgetDef(
    name: 'SizedBox',
    category: 'Layout',
    icon: Icons.open_with_rounded,
    color: Color(0xFF26C6DA),
  ),
  FlutterWidgetDef(
    name: 'Spacer',
    category: 'Layout',
    icon: Icons.space_bar_rounded,
    color: Color(0xFF4DD0E1),
  ),
  FlutterWidgetDef(
    name: 'AspectRatio',
    category: 'Layout',
    icon: Icons.aspect_ratio_rounded,
    color: Color(0xFF039BE5),
  ),
  FlutterWidgetDef(
    name: 'SafeArea',
    category: 'Layout',
    icon: Icons.phone_android_rounded,
    color: Color(0xFF0277BD),
  ),
  FlutterWidgetDef(
    name: 'SingleChildScrollView',
    category: 'Layout',
    icon: Icons.swipe_vertical_rounded,
    color: Color(0xFF01579B),
  ),
  FlutterWidgetDef(
    name: 'ListView',
    category: 'Layout',
    icon: Icons.list_rounded,
    color: Color(0xFF1A237E),
  ),
  FlutterWidgetDef(
    name: 'GridView',
    category: 'Layout',
    icon: Icons.grid_view_rounded,
    color: Color(0xFF283593),
  ),

  // ── Basic ────────────────────────────────────────────────────────────────
  FlutterWidgetDef(
    name: 'Text',
    category: 'Basic',
    icon: Icons.text_fields_rounded,
    color: Color(0xFF388E3C),
    defaultProperties: {'text': 'Hello World'},
  ),
  FlutterWidgetDef(
    name: 'Icon',
    category: 'Basic',
    icon: Icons.star_outline_rounded,
    color: Color(0xFF43A047),
    defaultProperties: {'icon': 'Icons.star', 'size': '24.0'},
  ),
  FlutterWidgetDef(
    name: 'Image',
    category: 'Basic',
    icon: Icons.image_outlined,
    color: Color(0xFF4CAF50),
    defaultProperties: {'url': 'https://picsum.photos/200', 'fit': 'BoxFit.cover'},
  ),
  FlutterWidgetDef(
    name: 'FlutterLogo',
    category: 'Basic',
    icon: Icons.flutter_dash,
    color: Color(0xFF0288D1),
    defaultProperties: {'size': '48.0'},
  ),
  FlutterWidgetDef(
    name: 'Placeholder',
    category: 'Basic',
    icon: Icons.crop_landscape_outlined,
    color: Color(0xFF9E9E9E),
  ),
  FlutterWidgetDef(
    name: 'Divider',
    category: 'Basic',
    icon: Icons.horizontal_rule_rounded,
    color: Color(0xFF757575),
  ),
  FlutterWidgetDef(
    name: 'VerticalDivider',
    category: 'Basic',
    icon: Icons.vertical_distribute_rounded,
    color: Color(0xFF757575),
  ),
  FlutterWidgetDef(
    name: 'CircularProgressIndicator',
    category: 'Basic',
    icon: Icons.loop_rounded,
    color: Color(0xFF00838F),
  ),
  FlutterWidgetDef(
    name: 'LinearProgressIndicator',
    category: 'Basic',
    icon: Icons.linear_scale_rounded,
    color: Color(0xFF00838F),
  ),
  FlutterWidgetDef(
    name: 'CircleAvatar',
    category: 'Basic',
    icon: Icons.account_circle_outlined,
    color: Color(0xFF5C6BC0),
    defaultProperties: {'radius': '24.0'},
  ),

  // ── Material ─────────────────────────────────────────────────────────────
  FlutterWidgetDef(
    name: 'Scaffold',
    category: 'Material',
    icon: Icons.phone_iphone_rounded,
    color: Color(0xFF6A1B9A),
  ),
  FlutterWidgetDef(
    name: 'AppBar',
    category: 'Material',
    icon: Icons.web_asset_rounded,
    color: Color(0xFF7B1FA2),
    defaultProperties: {'title': 'AppBar'},
  ),
  FlutterWidgetDef(
    name: 'BottomNavigationBar',
    category: 'Material',
    icon: Icons.menu_rounded,
    color: Color(0xFF8E24AA),
  ),
  FlutterWidgetDef(
    name: 'Card',
    category: 'Material',
    icon: Icons.credit_card_outlined,
    color: Color(0xFFAB47BC),
    defaultProperties: {'elevation': '2.0'},
  ),
  FlutterWidgetDef(
    name: 'ListTile',
    category: 'Material',
    icon: Icons.list_alt_outlined,
    color: Color(0xFFBA68C8),
    defaultProperties: {'title': 'Title'},
  ),
  FlutterWidgetDef(
    name: 'Chip',
    category: 'Material',
    icon: Icons.label_outline_rounded,
    color: Color(0xFFCE93D8),
    defaultProperties: {'label': 'Chip'},
  ),
  FlutterWidgetDef(
    name: 'Badge',
    category: 'Material',
    icon: Icons.circle_notifications_outlined,
    color: Color(0xFFE91E63),
    defaultProperties: {'label': '1'},
  ),
  FlutterWidgetDef(
    name: 'Tooltip',
    category: 'Material',
    icon: Icons.info_outline_rounded,
    color: Color(0xFF546E7A),
    defaultProperties: {'message': 'Tooltip'},
  ),
  FlutterWidgetDef(
    name: 'ClipRRect',
    category: 'Material',
    icon: Icons.rounded_corner_rounded,
    color: Color(0xFF455A64),
    defaultProperties: {'borderRadius': '8.0'},
  ),
  FlutterWidgetDef(
    name: 'ClipOval',
    category: 'Material',
    icon: Icons.circle_outlined,
    color: Color(0xFF37474F),
  ),
  FlutterWidgetDef(
    name: 'Opacity',
    category: 'Material',
    icon: Icons.opacity_rounded,
    color: Color(0xFF607D8B),
    defaultProperties: {'opacity': '0.5'},
  ),
  FlutterWidgetDef(
    name: 'InkWell',
    category: 'Material',
    icon: Icons.touch_app_outlined,
    color: Color(0xFF546E7A),
  ),
  FlutterWidgetDef(
    name: 'GestureDetector',
    category: 'Material',
    icon: Icons.gesture_rounded,
    color: Color(0xFF455A64),
  ),

  // ── Buttons ──────────────────────────────────────────────────────────────
  FlutterWidgetDef(
    name: 'ElevatedButton',
    category: 'Buttons',
    icon: Icons.smart_button_outlined,
    color: Color(0xFFE65100),
    defaultProperties: {'label': 'Button'},
  ),
  FlutterWidgetDef(
    name: 'FilledButton',
    category: 'Buttons',
    icon: Icons.rectangle_rounded,
    color: Color(0xFFBF360C),
    defaultProperties: {'label': 'Button'},
  ),
  FlutterWidgetDef(
    name: 'TextButton',
    category: 'Buttons',
    icon: Icons.text_snippet_outlined,
    color: Color(0xFFEF6C00),
    defaultProperties: {'label': 'Button'},
  ),
  FlutterWidgetDef(
    name: 'OutlinedButton',
    category: 'Buttons',
    icon: Icons.radio_button_unchecked_rounded,
    color: Color(0xFFF57C00),
    defaultProperties: {'label': 'Button'},
  ),
  FlutterWidgetDef(
    name: 'IconButton',
    category: 'Buttons',
    icon: Icons.crop_square_rounded,
    color: Color(0xFFFF8F00),
    defaultProperties: {'icon': 'Icons.add'},
  ),
  FlutterWidgetDef(
    name: 'FloatingActionButton',
    category: 'Buttons',
    icon: Icons.add_circle_outline_rounded,
    color: Color(0xFFFF6F00),
    defaultProperties: {'icon': 'Icons.add'},
  ),

  // ── Input ────────────────────────────────────────────────────────────────
  FlutterWidgetDef(
    name: 'TextField',
    category: 'Input',
    icon: Icons.text_fields_outlined,
    color: Color(0xFF00695C),
    defaultProperties: {'hintText': 'Enter text...'},
  ),
  FlutterWidgetDef(
    name: 'Switch',
    category: 'Input',
    icon: Icons.toggle_on_outlined,
    color: Color(0xFF00796B),
  ),
  FlutterWidgetDef(
    name: 'Checkbox',
    category: 'Input',
    icon: Icons.check_box_outlined,
    color: Color(0xFF00897B),
  ),
  FlutterWidgetDef(
    name: 'Slider',
    category: 'Input',
    icon: Icons.linear_scale_rounded,
    color: Color(0xFF009688),
    defaultProperties: {'value': '0.5'},
  ),
];

/// Unique categories in order.
const List<String> kWidgetCategories = [
  'Layout',
  'Basic',
  'Material',
  'Buttons',
  'Input',
];

/// Look up a def by widget type name. Returns null if not found.
FlutterWidgetDef? defForType(String type) {
  final idx = kFlutterWidgets.indexWhere((d) => d.name == type);
  return idx != -1 ? kFlutterWidgets[idx] : null;
}
