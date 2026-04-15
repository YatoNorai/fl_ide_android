import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/flutter_widget_catalog.dart';
import '../models/widget_node.dart';
import '../providers/visual_editor_provider.dart';
import 'interactive_widget_renderer.dart';

// ── Frame logical sizes ───────────────────────────────────────────────────────

Size _frameSize(PreviewMode mode) {
  switch (mode) {
    case PreviewMode.phone:
      return const Size(390, 844);
    case PreviewMode.tablet:
      return const Size(820, 1180);
    case PreviewMode.rectangle:
      return const Size(360, 640);
  }
}

// ── Main canvas ───────────────────────────────────────────────────────────────

/// The main interactive canvas for the visual editor.
/// Shows a phone/tablet device frame with real interactive widgets inside.
/// Requires [VisualEditorProvider] in scope.
class VisualEditorCanvas extends StatelessWidget {
  const VisualEditorCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualEditorProvider>();
    final cs = Theme.of(context).colorScheme;

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (details) {
        final def = details.data;
        provider.addWidget(
          WidgetNode(
            type: def.name,
            properties: Map<String, dynamic>.from(def.defaultProperties),
          ),
        );
      },
      builder: (context, candidates, rejected) {
        final hovering = candidates.isNotEmpty;
        return GestureDetector(
          onTap: () => provider.deselect(),
          child: Container(
            color: cs.surfaceContainerLowest,
            child: Stack(
              children: [
                // Dot-grid background
                CustomPaint(
                  painter: _DotGridPainter(
                    cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                  child: const SizedBox.expand(),
                ),

                // Hover highlight when dragging onto empty canvas
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
                            style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Empty state hint
                if (!provider.hasRoot && !hovering)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.widgets_outlined,
                          size: 48,
                          color: cs.outlineVariant,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Drag a widget here or tap from the palette',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Device frame with live preview
                if (provider.hasRoot)
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _DeviceFrame(provider: provider),
                      ),
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

// ── Device frame ──────────────────────────────────────────────────────────────

class _DeviceFrame extends StatelessWidget {
  final VisualEditorProvider provider;

  const _DeviceFrame({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mode = provider.previewMode;

    if (mode == PreviewMode.rectangle) {
      return Container(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 640),
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
          child: _InteractiveCanvas(
            root: provider.root!,
            mode: mode,
          ),
        ),
      );
    }

    final logical = _frameSize(mode);
    final scale = mode == PreviewMode.tablet ? 0.45 : 0.52;
    final w = logical.width * scale;
    final h = logical.height * scale;
    final r = mode == PreviewMode.tablet ? 20.0 : 44.0;
    final rScaled = r * scale;

    return SizedBox(
      width: w + 28,
      height: h + 48,
      child: Stack(
        children: [
          // Device shell outline
          Positioned.fill(
            child: CustomPaint(
              painter: _DeviceShellPainter(
                color: cs.outline.withValues(alpha: 0.6),
                radius: rScaled,
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
                child: Transform.scale(
                  scale: scale,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: logical.width,
                    height: logical.height,
                    child: _InteractiveCanvas(
                      root: provider.root!,
                      mode: mode,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Interactive canvas ────────────────────────────────────────────────────────

class _InteractiveCanvas extends StatelessWidget {
  final WidgetNode root;
  final PreviewMode mode;

  const _InteractiveCanvas({required this.root, required this.mode});

  @override
  Widget build(BuildContext context) {
    return MediaQuery(
      data: MediaQueryData(size: _frameSize(mode)),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        child: renderInteractive(root, context),
      ),
    );
  }
}

// ── Widget tree panel ─────────────────────────────────────────────────────────

/// A scrollable tree view of the widget hierarchy.
/// Shows indented nodes with the widget type name and icon.
/// Nodes are tappable to select them and switch to the Properties tab.
class WidgetTreePanel extends StatelessWidget {
  const WidgetTreePanel({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualEditorProvider>();

    if (!provider.hasRoot) {
      return Center(
        child: Text(
          'No widgets yet',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 14,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: _TreeNode(node: provider.root!, depth: 0),
    );
  }
}

// ── Tree node ─────────────────────────────────────────────────────────────────

class _TreeNode extends StatefulWidget {
  final WidgetNode node;
  final int depth;

  const _TreeNode({required this.node, required this.depth});

  @override
  State<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends State<_TreeNode> {
  bool _expanded = true;

  String _propSummary(WidgetNode node) {
    final p = node.properties;
    if (p.containsKey('text') && p['text'] != null) return ' · "${p['text']}"';
    if (p.containsKey('label') && p['label'] != null) return ' · "${p['label']}"';
    if (p.containsKey('title') && p['title'] != null) return ' · "${p['title']}"';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<VisualEditorProvider>();
    final cs = Theme.of(context).colorScheme;
    final def = defForType(widget.node.type);
    final color = def?.color ?? cs.primary;
    final isSelected = provider.selectedId == widget.node.id;
    final hasChildren =
        widget.node.canHaveChildren && widget.node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Row ───────────────────────────────────────────────────────────────
        GestureDetector(
          onTap: () {
            provider.select(widget.node.id);
            provider.setActiveTab(2); // switch to Properties
          },
          onLongPress: () {
            provider.removeWidget(widget.node.id);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            padding: EdgeInsets.only(
              left: 8.0 + widget.depth * 16.0,
              right: 8,
              top: 6,
              bottom: 6,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primaryContainer
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                // Expand / collapse toggle
                if (hasChildren)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AnimatedRotation(
                        turns: _expanded ? 0.25 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: color.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  )
                else
                  // Indent spacer so leaf nodes align with parent labels
                  const SizedBox(width: 20),

                // Widget type icon
                if (def != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(def.icon, size: 14, color: color),
                  ),

                // Type name + prop summary
                Expanded(
                  child: Text(
                    '${widget.node.type}${_propSummary(widget.node)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected ? cs.onPrimaryContainer : color,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Delete button
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => provider.removeWidget(widget.node.id),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Children (when expanded) ──────────────────────────────────────────
        if (hasChildren && _expanded)
          ...widget.node.children.map(
            (child) => _TreeNode(node: child, depth: widget.depth + 1),
          ),
      ],
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
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      paint,
    );
    // Home indicator bar
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
