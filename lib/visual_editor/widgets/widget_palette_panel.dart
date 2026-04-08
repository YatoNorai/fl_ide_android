import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/flutter_widget_catalog.dart';
import '../models/widget_node.dart';
import '../providers/visual_editor_provider.dart';

class WidgetPalettePanel extends StatefulWidget {
  const WidgetPalettePanel({super.key});

  @override
  State<WidgetPalettePanel> createState() => _WidgetPalettePanelState();
}

class _WidgetPalettePanelState extends State<WidgetPalettePanel> {
  String _search = '';
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = kFlutterWidgets.where((w) {
      final matchSearch = _search.isEmpty ||
          w.name.toLowerCase().contains(_search.toLowerCase());
      final matchCat =
          _selectedCategory == null || w.category == _selectedCategory;
      return matchSearch && matchCat;
    }).toList();

    final grouped = <String, List<FlutterWidgetDef>>{};
    for (final w in filtered) {
      grouped.putIfAbsent(w.category, () => []).add(w);
    }

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(right: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search widgets…',
                hintStyle: const TextStyle(fontSize: 12),
                prefixIcon: const Icon(Icons.search, size: 16),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            ),
          ),

          // Category filter chips
          if (_search.isEmpty)
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _catChip(null, 'All', cs),
                  for (final cat in kWidgetCategories) _catChip(cat, cat, cs),
                ],
              ),
            ),

          const SizedBox(height: 6),

          // Widget list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              children: [
                for (final cat in grouped.keys) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 6),
                    child: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: grouped[cat]!
                        .map((def) => _WidgetChip(def: def))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _catChip(String? cat, String label, ColorScheme cs) {
    final selected = _selectedCategory == cat;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _selectedCategory = cat),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A draggable chip representing a single Flutter widget.
class _WidgetChip extends StatelessWidget {
  final FlutterWidgetDef def;

  const _WidgetChip({required this.def});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Draggable<FlutterWidgetDef>(
      data: def,
      feedback: Material(
        color: Colors.transparent,
        child: _chip(cs, dragging: true),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _chip(cs)),
      child: GestureDetector(
        onTap: () {
          // Single tap also adds widget to canvas
          final provider =
              context.read<VisualEditorProvider>();
          final node = WidgetNode(
            type: def.name,
            properties: Map<String, dynamic>.from(def.defaultProperties),
          );
          provider.addWidget(node);
        },
        child: _chip(cs),
      ),
    );
  }

  Widget _chip(ColorScheme cs, {bool dragging = false}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      width: 84,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: dragging
            ? def.color.withValues(alpha: 0.18)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: dragging
              ? def.color.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(def.icon, size: 22, color: def.color),
          const SizedBox(height: 4),
          Text(
            def.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
