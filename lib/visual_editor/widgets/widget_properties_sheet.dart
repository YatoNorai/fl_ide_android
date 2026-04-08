import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/widget_node.dart';
import '../providers/visual_editor_provider.dart';

void showWidgetPropertiesSheet({
  required BuildContext context,
  required WidgetNode node,
  required VisualEditorProvider provider,
}) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PropertiesSheet(
      node: node,
      provider: provider,
    ),
  );
}

class _PropertiesSheet extends StatefulWidget {
  final WidgetNode node;
  final VisualEditorProvider provider;

  const _PropertiesSheet({required this.node, required this.provider});

  @override
  State<_PropertiesSheet> createState() => _PropertiesSheetState();
}

class _PropertiesSheetState extends State<_PropertiesSheet> {
  late WidgetNode node;
  late VisualEditorProvider provider;

  @override
  void initState() {
    super.initState();
    node = widget.node;
    provider = widget.provider;
  }

  void _set(String key, dynamic value) {
    provider.updateProperty(node.id, key, value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final props = _propsForType(node.type);

    return DraggableScrollableSheet(
      initialChildSize: 0.45,
      minChildSize: 0.25,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        node.type,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: cs.onPrimaryContainer,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Copy code button
                    IconButton(
                      onPressed: () {
                        Clipboard.setData(
                            ClipboardData(text: node.toCode()));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Code copied!'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      tooltip: 'Copy code',
                    ),
                    // Delete button
                    IconButton(
                      onPressed: () {
                        provider.removeWidget(node.id);
                        Navigator.pop(context);
                      },
                      icon:
                          Icon(Icons.delete_outline, size: 18, color: cs.error),
                      tooltip: 'Remove widget',
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Properties list
              Expanded(
                child: props.isEmpty
                    ? Center(
                        child: Text(
                          'No editable properties',
                          style:
                              TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                        ),
                      )
                    : ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                        children: [
                          for (final prop in props) _buildPropEditor(prop, cs),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPropEditor(_PropDef prop, ColorScheme cs) {
    final current = node.properties[prop.key]?.toString() ?? '';

    switch (prop.type) {
      case _PT.text:
        return _TextPropField(
          label: prop.label,
          initial: current.isNotEmpty ? current : prop.defaultValue ?? '',
          onChanged: (v) => _set(prop.key, v.isEmpty ? null : v),
        );

      case _PT.number:
        return _TextPropField(
          label: prop.label,
          initial: current.isNotEmpty ? current : prop.defaultValue ?? '',
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (v) => _set(prop.key, v.isEmpty ? null : v),
        );

      case _PT.color:
        return _ColorPropPicker(
          label: prop.label,
          current: current,
          onSelected: (v) => _set(prop.key, v),
          cs: cs,
        );

      case _PT.dropdown:
        return _DropdownProp(
          label: prop.label,
          current: current.isNotEmpty ? current : (prop.options?.first ?? ''),
          options: prop.options ?? [],
          onChanged: (v) => _set(prop.key, v),
          cs: cs,
        );

      case _PT.icon:
        return _IconPropPicker(
          label: prop.label,
          current: current.isNotEmpty ? current : (prop.defaultValue ?? 'Icons.star'),
          onSelected: (v) => _set(prop.key, v),
          cs: cs,
        );
    }
  }
}

// ── Property editors ──────────────────────────────────────────────────────────

class _TextPropField extends StatefulWidget {
  final String label;
  final String initial;
  final TextInputType? keyboardType;
  final ValueChanged<String> onChanged;

  const _TextPropField({
    required this.label,
    required this.initial,
    this.keyboardType,
    required this.onChanged,
  });

  @override
  State<_TextPropField> createState() => _TextPropFieldState();
}

class _TextPropFieldState extends State<_TextPropField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _ctrl,
        keyboardType: widget.keyboardType,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: const TextStyle(fontSize: 12),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        onChanged: widget.onChanged,
      ),
    );
  }
}

class _ColorPropPicker extends StatelessWidget {
  final String label;
  final String current;
  final ValueChanged<String> onSelected;
  final ColorScheme cs;

  const _ColorPropPicker({
    required this.label,
    required this.current,
    required this.onSelected,
    required this.cs,
  });

  static const _colors = [
    ('Colors.red', Color(0xFFF44336)),
    ('Colors.pink', Color(0xFFE91E63)),
    ('Colors.purple', Color(0xFF9C27B0)),
    ('Colors.deepPurple', Color(0xFF673AB7)),
    ('Colors.indigo', Color(0xFF3F51B5)),
    ('Colors.blue', Color(0xFF2196F3)),
    ('Colors.lightBlue', Color(0xFF03A9F4)),
    ('Colors.cyan', Color(0xFF00BCD4)),
    ('Colors.teal', Color(0xFF009688)),
    ('Colors.green', Color(0xFF4CAF50)),
    ('Colors.lightGreen', Color(0xFF8BC34A)),
    ('Colors.lime', Color(0xFFCDDC39)),
    ('Colors.yellow', Color(0xFFFFEB3B)),
    ('Colors.amber', Color(0xFFFFC107)),
    ('Colors.orange', Color(0xFFFF9800)),
    ('Colors.deepOrange', Color(0xFFFF5722)),
    ('Colors.brown', Color(0xFF795548)),
    ('Colors.grey', Color(0xFF9E9E9E)),
    ('Colors.blueGrey', Color(0xFF607D8B)),
    ('Colors.black', Color(0xFF000000)),
    ('Colors.white', Color(0xFFFFFFFF)),
    ('Colors.transparent', Color(0x00000000)),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _colors.map((c) {
              final selected = current == c.$1;
              return GestureDetector(
                onTap: () => onSelected(c.$1),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c.$2,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? cs.primary : cs.outlineVariant,
                      width: selected ? 2.5 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                                color: cs.primary.withValues(alpha: 0.5),
                                blurRadius: 6)
                          ]
                        : null,
                  ),
                  child: selected
                      ? Icon(Icons.check,
                          size: 14,
                          color: c.$2.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _DropdownProp extends StatelessWidget {
  final String label;
  final String current;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final ColorScheme cs;

  const _DropdownProp({
    required this.label,
    required this.current,
    required this.options,
    required this.onChanged,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = options.contains(current) ? current : options.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<String>(
        value: safeValue,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        ),
        style: const TextStyle(fontSize: 12),
        items: options
            .map((o) => DropdownMenuItem(value: o, child: Text(o)))
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _IconPropPicker extends StatelessWidget {
  final String label;
  final String current;
  final ValueChanged<String> onSelected;
  final ColorScheme cs;

  const _IconPropPicker({
    required this.label,
    required this.current,
    required this.onSelected,
    required this.cs,
  });

  static const _icons = [
    ('Icons.star', Icons.star),
    ('Icons.favorite', Icons.favorite),
    ('Icons.home', Icons.home),
    ('Icons.settings', Icons.settings),
    ('Icons.add', Icons.add),
    ('Icons.remove', Icons.remove),
    ('Icons.close', Icons.close),
    ('Icons.check', Icons.check),
    ('Icons.search', Icons.search),
    ('Icons.menu', Icons.menu),
    ('Icons.share', Icons.share),
    ('Icons.edit', Icons.edit),
    ('Icons.delete', Icons.delete),
    ('Icons.info', Icons.info),
    ('Icons.warning', Icons.warning),
    ('Icons.error', Icons.error),
    ('Icons.person', Icons.person),
    ('Icons.email', Icons.email),
    ('Icons.phone', Icons.phone),
    ('Icons.camera', Icons.camera),
    ('Icons.image', Icons.image),
    ('Icons.location_on', Icons.location_on),
    ('Icons.notifications', Icons.notifications),
    ('Icons.shopping_cart', Icons.shopping_cart),
    ('Icons.arrow_back', Icons.arrow_back),
    ('Icons.arrow_forward', Icons.arrow_forward),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _icons.map((ico) {
              final selected = current == ico.$1;
              return GestureDetector(
                onTap: () => onSelected(ico.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 100),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selected
                            ? cs.primary
                            : cs.outlineVariant.withValues(alpha: 0.4)),
                  ),
                  child: Icon(ico.$2,
                      size: 18,
                      color: selected ? cs.primary : cs.onSurfaceVariant),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Property definitions ──────────────────────────────────────────────────────

enum _PT { text, number, color, dropdown, icon }

class _PropDef {
  final String key;
  final String label;
  final _PT type;
  final String? defaultValue;
  final List<String>? options;

  const _PropDef(this.key, this.label, this.type,
      {this.defaultValue, this.options});
}

List<_PropDef> _propsForType(String type) {
  const mainAxisOptions = [
    'MainAxisAlignment.start',
    'MainAxisAlignment.center',
    'MainAxisAlignment.end',
    'MainAxisAlignment.spaceBetween',
    'MainAxisAlignment.spaceAround',
    'MainAxisAlignment.spaceEvenly',
  ];
  const crossAxisOptions = [
    'CrossAxisAlignment.start',
    'CrossAxisAlignment.center',
    'CrossAxisAlignment.end',
    'CrossAxisAlignment.stretch',
  ];
  const alignmentOptions = [
    'Alignment.topLeft', 'Alignment.topCenter', 'Alignment.topRight',
    'Alignment.centerLeft', 'Alignment.center', 'Alignment.centerRight',
    'Alignment.bottomLeft', 'Alignment.bottomCenter', 'Alignment.bottomRight',
  ];
  const fitOptions = [
    'BoxFit.contain', 'BoxFit.cover', 'BoxFit.fill',
    'BoxFit.fitHeight', 'BoxFit.fitWidth', 'BoxFit.none',
  ];
  const fontWeightOptions = [
    'FontWeight.w100', 'FontWeight.w300', 'FontWeight.w400',
    'FontWeight.w500', 'FontWeight.w600', 'FontWeight.w700',
    'FontWeight.w800', 'FontWeight.w900', 'FontWeight.bold',
  ];

  switch (type) {
    case 'Row':
    case 'Column':
      return [
        _PropDef('mainAxisAlignment', 'Main Axis Alignment', _PT.dropdown,
            options: mainAxisOptions,
            defaultValue: 'MainAxisAlignment.start'),
        _PropDef('crossAxisAlignment', 'Cross Axis Alignment', _PT.dropdown,
            options: crossAxisOptions,
            defaultValue: 'CrossAxisAlignment.center'),
      ];

    case 'Stack':
      return [
        _PropDef('alignment', 'Alignment', _PT.dropdown,
            options: alignmentOptions, defaultValue: 'Alignment.topLeft'),
      ];

    case 'Wrap':
      return [
        _PropDef('spacing', 'Spacing', _PT.number, defaultValue: '8.0'),
        _PropDef('runSpacing', 'Run Spacing', _PT.number, defaultValue: '8.0'),
      ];

    case 'Container':
      return [
        _PropDef('width', 'Width', _PT.number),
        _PropDef('height', 'Height', _PT.number),
        _PropDef('color', 'Color', _PT.color),
        _PropDef('borderRadius', 'Border Radius', _PT.number),
        _PropDef('padding', 'Padding (all)', _PT.number),
      ];

    case 'Padding':
      return [_PropDef('padding', 'Padding (all)', _PT.number, defaultValue: '8.0')];

    case 'Align':
      return [
        _PropDef('alignment', 'Alignment', _PT.dropdown,
            options: alignmentOptions, defaultValue: 'Alignment.center'),
      ];

    case 'Expanded':
    case 'Flexible':
      return [_PropDef('flex', 'Flex', _PT.number, defaultValue: '1')];

    case 'SizedBox':
      return [
        _PropDef('width', 'Width', _PT.number),
        _PropDef('height', 'Height', _PT.number),
      ];

    case 'Card':
      return [_PropDef('elevation', 'Elevation', _PT.number, defaultValue: '2.0')];

    case 'ClipRRect':
      return [_PropDef('borderRadius', 'Border Radius', _PT.number, defaultValue: '8.0')];

    case 'Opacity':
      return [_PropDef('opacity', 'Opacity (0-1)', _PT.number, defaultValue: '1.0')];

    case 'Text':
      return [
        _PropDef('text', 'Text', _PT.text, defaultValue: 'Hello World'),
        _PropDef('fontSize', 'Font Size', _PT.number),
        _PropDef('fontWeight', 'Font Weight', _PT.dropdown,
            options: fontWeightOptions),
        _PropDef('color', 'Color', _PT.color),
      ];

    case 'Icon':
      return [
        _PropDef('icon', 'Icon', _PT.icon, defaultValue: 'Icons.star'),
        _PropDef('size', 'Size', _PT.number, defaultValue: '24.0'),
        _PropDef('color', 'Color', _PT.color),
      ];

    case 'Image':
      return [
        _PropDef('url', 'Image URL', _PT.text),
        _PropDef('fit', 'Fit', _PT.dropdown, options: fitOptions, defaultValue: 'BoxFit.cover'),
      ];

    case 'FlutterLogo':
      return [_PropDef('size', 'Size', _PT.number, defaultValue: '48.0')];

    case 'CircleAvatar':
      return [
        _PropDef('radius', 'Radius', _PT.number, defaultValue: '24.0'),
        _PropDef('backgroundColor', 'Background Color', _PT.color),
      ];

    case 'ElevatedButton':
    case 'TextButton':
    case 'OutlinedButton':
    case 'FilledButton':
      return [_PropDef('label', 'Label', _PT.text, defaultValue: 'Button')];

    case 'IconButton':
    case 'FloatingActionButton':
      return [_PropDef('icon', 'Icon', _PT.icon, defaultValue: 'Icons.add')];

    case 'TextField':
      return [
        _PropDef('hintText', 'Hint Text', _PT.text),
        _PropDef('labelText', 'Label Text', _PT.text),
      ];

    case 'Slider':
      return [_PropDef('value', 'Initial Value (0-1)', _PT.number, defaultValue: '0.5')];

    case 'Chip':
    case 'Badge':
      return [_PropDef('label', 'Label', _PT.text, defaultValue: 'Label')];

    case 'ListTile':
      return [
        _PropDef('title', 'Title', _PT.text, defaultValue: 'Title'),
        _PropDef('subtitle', 'Subtitle', _PT.text),
      ];

    case 'AppBar':
    case 'Scaffold':
      return [_PropDef('appBarTitle', 'AppBar Title', _PT.text, defaultValue: 'AppBar')];

    case 'Tooltip':
      return [_PropDef('message', 'Message', _PT.text, defaultValue: 'Tooltip')];

    case 'Spacer':
      return [_PropDef('flex', 'Flex', _PT.number, defaultValue: '1')];

    case 'Material':
      return [_PropDef('color', 'Color', _PT.color)];

    default:
      return [];
  }
}
