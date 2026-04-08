import 'dart:io';

import 'package:code_editor/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/flutter_widget_catalog.dart';
import 'models/widget_node.dart';
import 'providers/visual_editor_provider.dart';
import 'utils/dart_widget_parser.dart';
import 'utils/widget_renderer.dart';
import 'widgets/widget_properties_sheet.dart';

/// Opens the visual editor as a full-screen route on top of the workspace.
/// If the active file is a Flutter widget, its tree is parsed and shown.
void openVisualEditor(BuildContext context) {
  WidgetNode? initialNode;
  String? sourcePath;
  String originalSource = '';
  String? parseError;

  final ep = context.read<EditorProvider>();
  final file = ep.activeFile;

  if (file == null) {
    parseError = 'Nenhum arquivo aberto no editor.';
  } else if (file.extension != 'dart') {
    parseError = 'O arquivo aberto não é um .dart.';
  } else {
    originalSource = file.controller?.content.fullText ?? '';
    sourcePath = file.path;
    if (originalSource.isEmpty) {
      parseError = 'Arquivo vazio.';
    } else {
      final parser = DartWidgetParser();
      if (!parser.isFlutterWidget(originalSource)) {
        parseError = 'O arquivo não é um StatelessWidget ou StatefulWidget.';
      } else {
        initialNode = parser.parseSource(originalSource);
        if (initialNode == null) {
          parseError = 'Não foi possível parsear o método build().';
        }
      }
    }
  }

  if (parseError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Visual Editor: $parseError'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => VisualEditorOverlay(
        initialNode: initialNode,
        sourcePath: sourcePath,
        originalSource: originalSource,
        parseError: parseError,
      ),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(1, 0),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 300),
    ),
  );
}

class VisualEditorOverlay extends StatelessWidget {
  final WidgetNode? initialNode;
  final String? sourcePath;
  final String originalSource;
  final String? parseError;

  const VisualEditorOverlay({
    super.key,
    this.initialNode,
    this.sourcePath,
    this.originalSource = '',
    this.parseError,
  });

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        final p = VisualEditorProvider();
        if (initialNode != null) p.setRoot(initialNode!);
        return p;
      },
      child: _VisualEditorBody(
        sourcePath: sourcePath,
        originalSource: originalSource,
        parseError: parseError,
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _VisualEditorBody extends StatelessWidget {
  final String? sourcePath;
  final String originalSource;
  final String? parseError;

  const _VisualEditorBody({
    this.sourcePath,
    this.originalSource = '',
    this.parseError,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark
                ? Brightness.light
                : Brightness.dark,
        systemNavigationBarColor: cs.surface,
      ),
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        body: Column(
          children: [
            // ── AppBar ────────────────────────────────────────────────────
            _TopBar(
              provider: provider,
              sourcePath: sourcePath,
              originalSource: originalSource,
            ),

            // ── Palette/tree panel slides down from top ───────────────────
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: provider.panelOpen
                  ? provider.activeTab == SidebarTab.build
                      ? _PalettePanel(provider: provider)
                      : _TreePanel(provider: provider)
                  : const SizedBox.shrink(),
            ),

            // ── Canvas (centered frame) ───────────────────────────────────
            Expanded(
              child: _CanvasArea(
                provider: provider,
                parseError: parseError,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Top app bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final VisualEditorProvider provider;
  final String? sourcePath;
  final String originalSource;

  const _TopBar({
    required this.provider,
    this.sourcePath,
    this.originalSource = '',
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      bottom: false,
      child: Container(
        height: kToolbarHeight,
        decoration: BoxDecoration(
          color: cs.surface,
          border: Border(
            bottom:
                BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          children: [
            // iOS-style back
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 28),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => Navigator.of(context).pop(),
            ),

            Text(
              'Visual Editor',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),

            const Spacer(),

            // Build tab toggle
            _TabToggle(
              icon: Icons.widgets_outlined,
              label: 'Build',
              active: provider.activeTab == SidebarTab.build &&
                  provider.panelOpen,
              activeColor: cs.primary,
              onTap: () => provider.selectTab(SidebarTab.build),
            ),

            // Tree tab toggle
            _TabToggle(
              icon: Icons.account_tree_outlined,
              label: 'Tree',
              active: provider.activeTab == SidebarTab.tree &&
                  provider.panelOpen,
              activeColor: cs.secondary,
              onTap: () => provider.selectTab(SidebarTab.tree),
            ),

            Container(
              width: 1,
              height: 20,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: cs.outlineVariant,
            ),

            // Preview mode cycle
            IconButton(
              icon: Icon(_previewIcon(provider.previewMode), size: 20),
              color: cs.tertiary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'Cycle frame',
              onPressed: () => _cyclePreview(provider),
            ),

            // Code
            IconButton(
              icon: const Icon(Icons.code_rounded, size: 20),
              color: cs.onSurfaceVariant,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: 'View code',
              onPressed: () => _showCode(context, provider),
            ),

            // Save to file
            if (provider.hasRoot && sourcePath != null)
              IconButton(
                icon: const Icon(Icons.save_outlined, size: 20),
                color: cs.primary,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Save to file',
                onPressed: () => _saveToFile(context, provider),
              ),

            // Clear
            if (provider.hasRoot)
              IconButton(
                icon: Icon(Icons.delete_sweep_outlined,
                    size: 20, color: cs.error),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 36, minHeight: 36),
                tooltip: 'Clear canvas',
                onPressed: () => _confirmClear(context, provider),
              ),

            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  IconData _previewIcon(PreviewMode mode) {
    switch (mode) {
      case PreviewMode.rectangle:
        return Icons.crop_landscape_rounded;
      case PreviewMode.phone:
        return Icons.phone_android_rounded;
      case PreviewMode.tablet:
        return Icons.tablet_android_rounded;
    }
  }

  void _cyclePreview(VisualEditorProvider p) {
    final next = PreviewMode.values[
        (PreviewMode.values.indexOf(p.previewMode) + 1) %
            PreviewMode.values.length];
    p.setPreviewMode(next);
  }

  void _showCode(BuildContext context, VisualEditorProvider provider) {
    final code = provider.generateFullCode();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas is empty')),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CodeSheet(code: code),
    );
  }

  void _confirmClear(BuildContext context, VisualEditorProvider provider) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear canvas?'),
        content: const Text('All widgets will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) provider.clearRoot();
    });
  }

  Future<void> _saveToFile(
      BuildContext context, VisualEditorProvider provider) async {
    if (sourcePath == null) return;
    final widgetCode = provider.generateCode();
    if (widgetCode.isEmpty) return;

    String newSource;
    if (originalSource.isNotEmpty) {
      // Replace the return expression in the original file
      newSource = DartWidgetParser().replaceReturnInBuild(originalSource, widgetCode);
    } else {
      newSource = provider.generateFullCode();
    }

    try {
      await File(sourcePath!).writeAsString(newSource);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Saved to ${sourcePath!.split('/').last.split('\\').last}'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _TabToggle extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _TabToggle({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16,
                color: active ? activeColor : cs.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: active ? activeColor : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Palette panel (drops from top) ────────────────────────────────────────────

class _PalettePanel extends StatefulWidget {
  final VisualEditorProvider provider;

  const _PalettePanel({required this.provider});

  @override
  State<_PalettePanel> createState() => _PalettePanelState();
}

class _PalettePanelState extends State<_PalettePanel> {
  String? _selectedCategory;
  String _search = '';

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

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom:
              BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
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
                fillColor:
                    cs.surfaceContainerHighest.withValues(alpha: 0.5),
              ),
            ),
          ),

          // Category chips
          if (_search.isEmpty)
            SizedBox(
              height: 30,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _CatChip(
                    label: 'All',
                    selected: _selectedCategory == null,
                    onTap: () => setState(() => _selectedCategory = null),
                  ),
                  for (final cat in kWidgetCategories)
                    _CatChip(
                      label: cat,
                      selected: _selectedCategory == cat,
                      onTap: () =>
                          setState(() => _selectedCategory = cat),
                    ),
                ],
              ),
            ),

          const SizedBox(height: 6),

          // 2-row horizontal scroll
          SizedBox(
            height: 96,
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              scrollDirection: Axis.horizontal,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 0.38,
                crossAxisSpacing: 6,
                mainAxisSpacing: 8,
              ),
              itemCount: filtered.length,
              itemBuilder: (ctx, i) => _WidgetTile(
                def: filtered[i],
                provider: widget.provider,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CatChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
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
              color:
                  selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

class _WidgetTile extends StatelessWidget {
  final FlutterWidgetDef def;
  final VisualEditorProvider provider;

  const _WidgetTile({required this.def, required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Draggable<FlutterWidgetDef>(
      data: def,
      feedback: Material(
        color: Colors.transparent,
        child: _tile(cs, dragging: true),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: _tile(cs)),
      child: GestureDetector(
        onTap: () {
          final node = WidgetNode(
            type: def.name,
            properties: Map<String, dynamic>.from(def.defaultProperties),
          );
          provider.addWidget(node);
        },
        child: _tile(cs),
      ),
    );
  }

  Widget _tile(ColorScheme cs, {bool dragging = false}) {
    return Container(
      decoration: BoxDecoration(
        color: dragging
            ? def.color.withValues(alpha: 0.15)
            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: dragging
              ? def.color.withValues(alpha: 0.6)
              : cs.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10, right: 8),
            child: Icon(def.icon, size: 15, color: def.color),
          ),
          Expanded(
            child: Text(
              def.name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
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

// ── Canvas area ───────────────────────────────────────────────────────────────

class _CanvasArea extends StatelessWidget {
  final VisualEditorProvider provider;
  final String? parseError;

  const _CanvasArea({required this.provider, this.parseError});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (d) {
        final node = WidgetNode(
          type: d.data.name,
          properties: Map<String, dynamic>.from(d.data.defaultProperties),
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
              fit: StackFit.expand,
              children: [
                // Dot grid background
                CustomPaint(
                  painter: _DotGridPainter(
                      cs.outlineVariant.withValues(alpha: 0.35)),
                ),

                // Drop hint when empty + dragging
                if (hovering && !provider.hasRoot)
                  Center(
                    child: Container(
                      width: 220,
                      height: 110,
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.primary, width: 2),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded,
                              color: cs.primary, size: 32),
                          const SizedBox(height: 6),
                          Text(
                            'Soltar aqui',
                            style: TextStyle(
                                color: cs.primary,
                                fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Empty state
                if (!provider.hasRoot && !hovering)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          parseError != null
                              ? Icons.error_outline
                              : Icons.widgets_outlined,
                          size: 52,
                          color: parseError != null
                              ? cs.error
                              : cs.outlineVariant,
                        ),
                        const SizedBox(height: 14),
                        Text(
                          parseError ??
                              'Arraste um widget para cá\nou toque em um na paleta',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: parseError != null
                                ? cs.error
                                : cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Widget tree — centered and scaled to fit
                if (provider.hasRoot)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: FittedBox(
                        fit: BoxFit.contain,
                        child: _FramedNode(
                          node: provider.root!,
                          provider: provider,
                          mode: provider.previewMode,
                        ),
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

// ── Device frame wrapper ──────────────────────────────────────────────────────

class _FramedNode extends StatelessWidget {
  final WidgetNode node;
  final VisualEditorProvider provider;
  final PreviewMode mode;

  const _FramedNode({
    required this.node,
    required this.provider,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Canvas always shows real rendered widgets.
    // The Tree panel (via Tree tab) handles structural editing.
    final Widget screenContent = _safeRender(node);

    if (mode == PreviewMode.rectangle) {
      return Container(
        width: 360,
        height: 560,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: cs.outlineVariant),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: screenContent,
      );
    }

    const scale = 0.56;
    final logical = mode == PreviewMode.tablet
        ? const Size(820, 1180)
        : const Size(390, 844);
    final w = logical.width * scale;
    final h = logical.height * scale;
    final r = (mode == PreviewMode.tablet ? 20.0 : 44.0) * scale;

    return SizedBox(
      width: w + 30,
      height: h + 52,
      child: Stack(
        children: [
          // Shell outline
          Positioned.fill(
            child: CustomPaint(
              painter: _DevicePainter(
                  color: cs.outline.withValues(alpha: 0.55), radius: r),
            ),
          ),
          // Notch hint
          Positioned(
            top: 24 + 6,
            left: (w + 30) / 2 - 30,
            child: Container(
              width: 60,
              height: 6,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          // Screen
          Positioned(
            left: 15,
            top: 26,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(r - 2),
              child: Container(
                width: w,
                height: h,
                color: Colors.white,
                child: screenContent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _safeRender(WidgetNode n) {
    try {
      final rendered = WidgetRenderer.render(n);
      // Provide MediaQuery with phone dimensions so Scaffold/AppBar/etc
      // know the screen size. Material gives background + ink effects.
      return MediaQuery(
        data: const MediaQueryData(
          size: Size(390, 844),
          devicePixelRatio: 1.0,
        ),
        child: Material(
          type: MaterialType.canvas,
          color: Colors.white,
          child: rendered,
        ),
      );
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Render error:\n$e',
            style: const TextStyle(color: Colors.red, fontSize: 10),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }
}

// ── Recursive node box ────────────────────────────────────────────────────────

class _NodeBox extends StatelessWidget {
  final WidgetNode node;
  final VisualEditorProvider provider;
  final int depth;

  const _NodeBox({
    required this.node,
    required this.provider,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final def = defForType(node.type);
    final color = def?.color ?? cs.primary;
    final isSelected = provider.selectedId == node.id;

    return DragTarget<FlutterWidgetDef>(
      onAcceptWithDetails: (d) {
        if (!node.canHaveChildren) return;
        provider.addWidget(
          WidgetNode(
            type: d.data.name,
            properties: Map<String, dynamic>.from(d.data.defaultProperties),
          ),
          parentId: node.id,
        );
      },
      builder: (ctx, defCands, _) {
        return DragTarget<WidgetNode>(
          onAcceptWithDetails: (d) {
            if (d.data.id == node.id) return;
            provider.moveWidget(d.data.id, node.id);
          },
          builder: (ctx2, nodeCands, _) {
            final hover = (defCands.isNotEmpty || nodeCands.isNotEmpty) &&
                node.canHaveChildren;

            return LongPressDraggable<WidgetNode>(
              data: node,
              hapticFeedbackOnStart: true,
              feedback: Material(
                color: Colors.transparent,
                child: _NodeChip(node: node, color: color, opacity: 0.8),
              ),
              childWhenDragging: Opacity(
                opacity: 0.25,
                child: _nodeContent(cs, color, isSelected, hover, context),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  provider.select(node.id);
                  showWidgetPropertiesSheet(
                    context: context,
                    node: node,
                    provider: provider,
                  );
                },
                child: _nodeContent(cs, color, isSelected, hover, context),
              ),
            );
          },
        );
      },
    );
  }

  Widget _nodeContent(ColorScheme cs, Color color, bool selected, bool hover,
      BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: EdgeInsets.all(depth == 0 ? 0 : 3),
      constraints: const BoxConstraints(minWidth: 72, minHeight: 40),
      decoration: BoxDecoration(
        color: hover
            ? color.withValues(alpha: 0.2)
            : color.withValues(alpha: selected ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? color
              : hover
                  ? color.withValues(alpha: 0.8)
                  : color.withValues(alpha: 0.3),
          width: selected ? 2.0 : 1.0,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (defForType(node.type) != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(defForType(node.type)!.icon,
                        size: 11, color: color),
                  ),
                Flexible(
                  child: Text(
                    _labelFor(node),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          if (node.canHaveMultipleChildren)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: node.children.isEmpty
                  ? _dropHint(color)
                  : Wrap(
                      spacing: 2,
                      runSpacing: 2,
                      children: node.children
                          .map((c) => _NodeBox(
                              node: c,
                              provider: provider,
                              depth: depth + 1))
                          .toList(),
                    ),
            )
          else if (node.canHaveChildren)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: node.children.isEmpty
                  ? _dropHint(color)
                  : _NodeBox(
                      node: node.children.first,
                      provider: provider,
                      depth: depth + 1),
            ),
        ],
      ),
    );
  }

  String _labelFor(WidgetNode n) {
    final p = n.properties;
    String name = n.type;
    if (p.containsKey('text')) {
      name += ' · "${p['text']}"';
    } else if (p.containsKey('label')) {
      name += ' · "${p['label']}"';
    } else if (p.containsKey('title')) {
      name += ' · "${p['title']}"';
    }
    return name;
  }

  Widget _dropHint(Color color) => Container(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border:
              Border.all(color: color.withValues(alpha: 0.25), width: 1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Center(
          child: Text(
            'soltar filho aqui',
            style: TextStyle(
              fontSize: 8.5,
              color: color.withValues(alpha: 0.45),
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
}

class _NodeChip extends StatelessWidget {
  final WidgetNode node;
  final Color color;
  final double opacity;

  const _NodeChip(
      {required this.node, required this.color, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color),
        ),
        child: Text(
          node.type,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

// ── Widget tree panel ─────────────────────────────────────────────────────────

class _TreePanel extends StatelessWidget {
  final VisualEditorProvider provider;

  const _TreePanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom:
              BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              'Widget Tree',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: cs.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: provider.root == null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Empty',
                        style: TextStyle(
                            color: cs.outlineVariant, fontSize: 13),
                      ),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      _TreeItem(
                          node: provider.root!,
                          provider: provider,
                          depth: 0),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TreeItem extends StatelessWidget {
  final WidgetNode node;
  final VisualEditorProvider provider;
  final int depth;

  const _TreeItem({
    required this.node,
    required this.provider,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final def = defForType(node.type);
    final color = def?.color ?? cs.primary;
    final isSelected = provider.selectedId == node.id;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => provider.select(node.id),
          child: Container(
            margin: EdgeInsets.only(left: depth * 12.0, bottom: 2),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                if (def != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(def.icon, size: 14, color: color),
                  ),
                Expanded(
                  child: Text(
                    node.type,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? color : cs.onSurface,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => provider.removeWidget(node.id),
                  child: Icon(Icons.close,
                      size: 12,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
        ),
        for (final child in node.children)
          _TreeItem(node: child, provider: provider, depth: depth + 1),
      ],
    );
  }
}

// ── Code sheet ────────────────────────────────────────────────────────────────

class _CodeSheet extends StatelessWidget {
  final String code;

  const _CodeSheet({required this.code});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, ctrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
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
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Generated Code',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Code copied to clipboard!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy'),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: ctrl,
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(
                    code,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: cs.onSurface,
                      height: 1.6,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Painters ──────────────────────────────────────────────────────────────────

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

class _DevicePainter extends CustomPainter {
  final Color color;
  final double radius;

  const _DevicePainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Radius.circular(radius)),
      paint,
    );
    final bw = size.width * 0.35;
    final by = size.height - 7;
    canvas.drawLine(
      Offset((size.width - bw) / 2, by),
      Offset((size.width + bw) / 2, by),
      Paint()
        ..color = color.withValues(alpha: 0.45)
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DevicePainter old) =>
      old.color != color || old.radius != radius;
}
