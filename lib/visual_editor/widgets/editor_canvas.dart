import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/flutter_widget_catalog.dart';
import '../models/widget_node.dart';
import '../providers/visual_editor_provider.dart';
import '../utils/widget_renderer.dart';
import 'widget_properties_sheet.dart';

// ── Device frame definitions ──────────────────────────────────────────────────

const _kPhone = Size(390, 844);
const _kTablet = Size(820, 1180);

// ── Main canvas ───────────────────────────────────────────────────────────────

class EditorCanvas extends StatelessWidget {
  const EditorCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (details) {
        final def = details.data;
        final node = WidgetNode(
          type: def.name,
          properties: Map<String, dynamic>.from(def.defaultProperties),
        );
        provider.addWidget(node);
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return GestureDetector(
          onTap: () => provider.deselect(),
          child: Container(
            color: cs.surfaceContainerLowest,
            child: Stack(
              children: [
                // Dot grid background
                CustomPaint(
                  painter: _DotGridPainter(cs.outlineVariant.withValues(alpha: 0.4)),
                  child: const SizedBox.expand(),
                ),

                // Hover highlight for empty drop
                if (hovering && !provider.hasRoot)
                  Center(
                    child: Container(
                      width: 200,
                      height: 120,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: cs.primary,
                          width: 2,
                          strokeAlign: BorderSide.strokeAlignInside,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, color: cs.primary, size: 32),
                          const SizedBox(height: 6),
                          Text(
                            'Drop here',
                            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Widget preview frame
                if (provider.hasRoot)
                  Center(child: _PreviewFrame(provider: provider)),

                // Empty state hint
                if (!provider.hasRoot && !hovering)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.widgets_outlined,
                            size: 48, color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'Drag a widget here\nor tap one from the palette',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Preview frame (phone / tablet / rectangle) ────────────────────────────────

class _PreviewFrame extends StatelessWidget {
  final VisualEditorProvider provider;

  const _PreviewFrame({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mode = provider.previewMode;

    // Use real rendering in preview (Build) tab, wireframe in Tree tab
    final useReal = provider.activeTab != SidebarTab.tree;
    Widget canvas = useReal
        ? _RealWidgetCanvas(root: provider.root!)
        : _WidgetTreeCanvas(root: provider.root!);

    if (mode == PreviewMode.rectangle) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 640),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(11),
          child: canvas,
        ),
      );
    }

    final logical =
        mode == PreviewMode.tablet ? _kTablet : _kPhone;
    const scale = 0.55;
    final w = logical.width * scale;
    final h = logical.height * scale;
    final r = mode == PreviewMode.tablet ? 20.0 : 44.0;

    return SizedBox(
      width: w + 28,
      height: h + 48,
      child: Stack(
        children: [
          // Device shell
          Positioned.fill(
            child: CustomPaint(
              painter: _DeviceShellPainter(
                color: cs.outline.withValues(alpha: 0.6),
                radius: r * scale,
              ),
            ),
          ),
          // Screen content
          Positioned(
            left: 14,
            top: 24,
            child: ClipRRect(
              borderRadius: BorderRadius.circular((r - 4) * scale),
              child: SizedBox(
                width: w,
                height: h,
                child: canvas,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Real widget renderer (preview mode) ───────────────────────────────────────

class _RealWidgetCanvas extends StatelessWidget {
  final WidgetNode root;

  const _RealWidgetCanvas({required this.root});

  @override
  Widget build(BuildContext context) {
    try {
      return WidgetRenderer.render(root, isRoot: true);
    } catch (_) {
      return const Center(
        child: Text('Preview error', style: TextStyle(color: Colors.red)),
      );
    }
  }
}

// ── Wireframe renderer (tree mode) ────────────────────────────────────────────

class _WidgetTreeCanvas extends StatelessWidget {
  final WidgetNode root;

  const _WidgetTreeCanvas({required this.root});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _NodeBox(node: root, depth: 0),
      ),
    );
  }
}

class _NodeBox extends StatelessWidget {
  final WidgetNode node;
  final int depth;

  const _NodeBox({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();
    final def = defForType(node.type);
    final color = def?.color ?? cs.primary;
    final isSelected = provider.selectedId == node.id;

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (details) {
        if (!node.canHaveChildren) return;
        final newNode = WidgetNode(
          type: details.data.name,
          properties:
              Map<String, dynamic>.from(details.data.defaultProperties),
        );
        provider.addWidget(newNode, parentId: node.id);
      },
      builder: (ctx, cands, _) {
        final dropHover = cands.isNotEmpty && node.canHaveChildren;

        return LongPressDraggable<WidgetNode>(
          data: node,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.75,
              child: _NodeLabel(node: node, color: color, selected: false),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: _buildBox(cs, color, isSelected, dropHover, provider, context)),
          onDragCompleted: () {},
          child: DragTarget<WidgetNode>(
            onAcceptWithDetails: (details) {
              final dragged = details.data;
              if (dragged.id == node.id) return;
              provider.moveWidget(dragged.id, node.id);
            },
            builder: (ctx2, nodeCands, _) => _buildBox(
                cs, color, isSelected, dropHover || nodeCands.isNotEmpty, provider, context),
          ),
        );
      },
    );
  }

  Widget _buildBox(ColorScheme cs, Color color, bool selected, bool hover,
      VisualEditorProvider provider, BuildContext context) {
    return GestureDetector(
      onTap: () {
        provider.select(node.id);
        showWidgetPropertiesSheet(
          context: context,
          node: node,
          provider: provider,
        );
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: EdgeInsets.all(depth == 0 ? 0 : 4),
        decoration: BoxDecoration(
          color: hover
              ? color.withValues(alpha: 0.18)
              : color.withValues(alpha: selected ? 0.15 : 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? color
                : hover
                    ? color.withValues(alpha: 0.7)
                    : color.withValues(alpha: 0.35),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NodeLabel(node: node, color: color, selected: selected),
            if (node.canHaveMultipleChildren)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: node.children.isEmpty
                    ? _EmptyChildHint(color: color)
                    : Wrap(
                        children: node.children
                            .map((c) =>
                                _NodeBox(node: c, depth: depth + 1))
                            .toList(),
                      ),
              )
            else if (node.canHaveChildren)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: node.children.isEmpty
                    ? _EmptyChildHint(color: color)
                    : _NodeBox(node: node.children.first, depth: depth + 1),
              ),
          ],
        ),
      ),
    );
  }
}

// workaround — we use a stateful wrapper so we have context
class _NodeBoxWrapper extends StatelessWidget {
  final WidgetNode node;
  final int depth;

  const _NodeBoxWrapper({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) => _NodeBoxWithContext(node: node, depth: depth);
}

class _NodeBoxWithContext extends StatelessWidget {
  final WidgetNode node;
  final int depth;

  const _NodeBoxWithContext({required this.node, required this.depth});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();
    final def = defForType(node.type);
    final color = def?.color ?? cs.primary;
    final isSelected = provider.selectedId == node.id;

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (details) {
        if (!node.canHaveChildren) return;
        final newNode = WidgetNode(
          type: details.data.name,
          properties: Map<String, dynamic>.from(details.data.defaultProperties),
        );
        provider.addWidget(newNode, parentId: node.id);
      },
      builder: (ctx, cands, _) {
        final dropHover = cands.isNotEmpty && node.canHaveChildren;

        return LongPressDraggable<WidgetNode>(
          data: node,
          feedback: Material(
            color: Colors.transparent,
            child: Opacity(
              opacity: 0.75,
              child: _NodeLabel(node: node, color: color, selected: false),
            ),
          ),
          childWhenDragging: Opacity(
            opacity: 0.3,
            child: _box(cs, color, isSelected, dropHover, provider, context),
          ),
          child: DragTarget<WidgetNode>(
            onAcceptWithDetails: (d) {
              if (d.data.id != node.id) provider.moveWidget(d.data.id, node.id);
            },
            builder: (ctx2, nodeCands, _) => _box(
                cs, color, isSelected,
                dropHover || nodeCands.isNotEmpty, provider, context),
          ),
        );
      },
    );
  }

  Widget _box(ColorScheme cs, Color color, bool selected, bool hover,
      VisualEditorProvider provider, BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        provider.select(node.id);
        showWidgetPropertiesSheet(context: context, node: node, provider: provider);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: EdgeInsets.all(depth == 0 ? 0 : 4),
        constraints: const BoxConstraints(minWidth: 60, minHeight: 36),
        decoration: BoxDecoration(
          color: hover
              ? color.withValues(alpha: 0.18)
              : color.withValues(alpha: selected ? 0.14 : 0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected
                ? color
                : hover
                    ? color.withValues(alpha: 0.7)
                    : color.withValues(alpha: 0.32),
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NodeLabel(node: node, color: color, selected: selected),
            if (node.canHaveMultipleChildren)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: node.children.isEmpty
                    ? _EmptyChildHint(color: color)
                    : Wrap(
                        spacing: 0,
                        runSpacing: 0,
                        children: node.children
                            .map((c) => _NodeBoxWrapper(node: c, depth: depth + 1))
                            .toList(),
                      ),
              )
            else if (node.canHaveChildren)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: node.children.isEmpty
                    ? _EmptyChildHint(color: color)
                    : _NodeBoxWrapper(node: node.children.first, depth: depth + 1),
              ),
          ],
        ),
      ),
    );
  }
}

class _NodeLabel extends StatelessWidget {
  final WidgetNode node;
  final Color color;
  final bool selected;

  const _NodeLabel({
    required this.node,
    required this.color,
    required this.selected,
  });

  @override
  Widget build(BuildContext context) {
    final def = defForType(node.type);
    String label = node.type;
    // Show most relevant property as hint
    final p = node.properties;
    if (p.containsKey('text')) label += ' · "${p['text']}"';
    else if (p.containsKey('label')) label += ' · "${p['label']}"';
    else if (p.containsKey('title')) label += ' · "${p['title']}"';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (def != null)
            Padding(
              padding: const EdgeInsets.only(right: 5),
              child: Icon(def.icon, size: 12, color: color),
            ),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyChildHint extends StatelessWidget {
  final Color color;

  const _EmptyChildHint({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(
            color: color.withValues(alpha: 0.3), style: BorderStyle.solid),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          'drop child here',
          style: TextStyle(
            fontSize: 9,
            color: color.withValues(alpha: 0.5),
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
    );
  }
}

// ── Dot grid background ───────────────────────────────────────────────────────

class _DotGridPainter extends CustomPainter {
  final Color color;

  const _DotGridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 22.0;
    final paint = Paint()..color = color;
    for (double x = spacing; x < size.width; x += spacing) {
      for (double y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}

// ── Device shell painter ──────────────────────────────────────────────────────

class _DeviceShellPainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DeviceShellPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    final rect =
        Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    // Home indicator
    final indW = size.width * 0.35;
    final y = size.height - 6;
    canvas.drawLine(
      Offset((size.width - indW) / 2, y),
      Offset((size.width + indW) / 2, y),
      Paint()
        ..color = color.withValues(alpha: 0.5)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DeviceShellPainter old) =>
      old.color != color || old.radius != radius;
}

// ── Public canvas entry point (uses wrapper with context) ─────────────────────

class CanvasWithContext extends StatelessWidget {
  final VisualEditorProvider provider;

  const CanvasWithContext({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (details) {
        final def = details.data;
        final node = WidgetNode(
          type: def.name,
          properties: Map<String, dynamic>.from(def.defaultProperties),
        );
        provider.addWidget(node);
      },
      builder: (ctx, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return GestureDetector(
          onTap: () => provider.deselect(),
          child: Container(
            color: cs.surfaceContainerLowest,
            child: Stack(
              children: [
                CustomPaint(
                  painter: _DotGridPainter(cs.outlineVariant.withValues(alpha: 0.35)),
                  child: const SizedBox.expand(),
                ),
                if (hovering && !provider.hasRoot)
                  Center(
                    child: Container(
                      width: 200,
                      height: 120,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.primary, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, color: cs.primary, size: 32),
                          const SizedBox(height: 6),
                          Text('Drop here',
                              style: TextStyle(
                                  color: cs.primary,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                if (provider.hasRoot)
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _PreviewFrame(provider: provider),
                      ),
                    ),
                  ),
                if (!provider.hasRoot && !hovering)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.widgets_outlined,
                            size: 48, color: cs.outlineVariant),
                        const SizedBox(height: 12),
                        Text(
                          'Arraste um widget aqui\nou toque na paleta',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: cs.onSurfaceVariant, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// Replace _PreviewFrame to use the context-aware wrapper
extension on _PreviewFrame {
  // This is handled above — _NodeBoxWrapper → _NodeBoxWithContext
}
