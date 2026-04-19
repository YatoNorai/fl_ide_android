import 'dart:io';

import 'package:code_editor/code_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'models/flutter_widget_catalog.dart';
import 'models/widget_node.dart';
import 'providers/visual_editor_provider.dart';
import 'utils/dart_widget_parser.dart';
import 'widgets/rfw_renderer.dart';
import 'widgets/widget_properties_sheet.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

/// Opens the visual editor as a full-screen route on top of the workspace.
/// Returns without navigating when the active file is not a Flutter widget.
void openVisualEditor(BuildContext context) {
  WidgetNode? initialNode;
  String? sourcePath;
  String originalSource = '';
  String? parseError;

  final ep = context.read<EditorProvider>();
  // topActiveFile is the last-focused file in the main (top) editor panel.
  // activeFile could point to a bottom-panel tab (LSP output, etc.), so we
  // prefer topActiveFile to always get the file the user is actually editing.
  final file = ep.topActiveFile ?? ep.activeFile;

  if (file == null) {
    parseError = 'Nenhum arquivo aberto no editor.';
  } else if (file.extension != 'dart') {
    parseError = 'O arquivo aberto não é um .dart.';
  } else {
    sourcePath = file.path;
    // Prefer the live controller text (unsaved edits are included).
    // Fall back to disk content when the controller is not yet attached.
    final controllerText = file.controller?.content.fullText ?? '';
    if (controllerText.isNotEmpty) {
      originalSource = controllerText;
    } else if (sourcePath != null) {
      try {
        originalSource = File(sourcePath).readAsStringSync();
      } catch (_) {}
    }

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
        content: Text('Editor Visual: $parseError'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    return;
  }

  final capturedFile = file!;
  void onCodeChanged(String newSource) {
    capturedFile.controller?.setText(newSource);
    ep.markDirty();
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => VisualEditorOverlay(
        initialNode: initialNode,
        sourcePath: sourcePath,
        originalSource: originalSource,
        onCodeChanged: onCodeChanged,
      ),
    ),
  );
}

// ── Overlay wrapper ───────────────────────────────────────────────────────────

class VisualEditorOverlay extends StatelessWidget {
  final WidgetNode? initialNode;
  final String? sourcePath;
  final String originalSource;
  final String? parseError;
  final void Function(String newSource)? onCodeChanged;

  const VisualEditorOverlay({
    super.key,
    this.initialNode,
    this.sourcePath,
    this.originalSource = '',
    this.parseError,
    this.onCodeChanged,
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
        onCodeChanged: onCodeChanged,
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _VisualEditorBody extends StatefulWidget {
  final String? sourcePath;
  final String originalSource;
  final void Function(String newSource)? onCodeChanged;

  const _VisualEditorBody({
    this.sourcePath,
    this.originalSource = '',
    this.onCodeChanged,
  });

  @override
  State<_VisualEditorBody> createState() => _VisualEditorBodyState();
}

class _VisualEditorBodyState extends State<_VisualEditorBody> {
  late String _originalSource;
  bool _hasUnappliedChanges = false;
  late VisualEditorProvider _provider;
  bool _providerListenerAttached = false;

  @override
  void initState() {
    super.initState();
    _originalSource = widget.originalSource;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_providerListenerAttached) {
      _provider = context.read<VisualEditorProvider>();
      _provider.addListener(_onProviderChange);
      _providerListenerAttached = true;
    }
  }

  @override
  void dispose() {
    if (_providerListenerAttached) {
      _provider.removeListener(_onProviderChange);
    }
    super.dispose();
  }

  void _onProviderChange() {
    if (!mounted) return;
    setState(() => _hasUnappliedChanges = true);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _applyChanges(VisualEditorProvider provider) {
    final newSource = provider.generateSource(_originalSource);
    if (newSource == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Falha ao gerar código.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    widget.onCodeChanged?.call(newSource);
    setState(() {
      _originalSource = newSource;
      _hasUnappliedChanges = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Código atualizado!'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleBack(VisualEditorProvider provider) async {
    if (!_hasUnappliedChanges) {
      Navigator.of(context).pop();
      return;
    }
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Aplicar alterações?'),
        content: const Text(
          'Há alterações visuais que ainda não foram aplicadas ao código.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Descartar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (result == true) {
      _applyChanges(provider);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();

    final fileName = widget.sourcePath != null
        ? widget.sourcePath!.split('/').last.split('\\').last
        : 'Sem arquivo';

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
        appBar: AppBar(
          leading: BackButton(
            onPressed: () => _handleBack(provider),
          ),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Editor Visual',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                ),
              ),
              Text(
                fileName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          centerTitle: true,
          actions: [
            // Undo
            Consumer<VisualEditorProvider>(
              builder: (_, p, __) => IconButton(
                icon: const Icon(Icons.undo),
                onPressed: p.canUndo ? p.undo : null,
                tooltip: 'Desfazer',
              ),
            ),
            // Redo
            Consumer<VisualEditorProvider>(
              builder: (_, p, __) => IconButton(
                icon: const Icon(Icons.redo),
                onPressed: p.canRedo ? p.redo : null,
                tooltip: 'Refazer',
              ),
            ),
            // Preview mode popup
            Consumer<VisualEditorProvider>(
              builder: (_, p, __) => PopupMenuButton<PreviewMode>(
                icon: Icon(_modeIcon(p.previewMode)),
                tooltip: 'Preview',
                onSelected: p.setPreviewMode,
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: PreviewMode.phone,
                    child: Row(children: [
                      Icon(Icons.smartphone),
                      SizedBox(width: 8),
                      Text('Telefone'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: PreviewMode.tablet,
                    child: Row(children: [
                      Icon(Icons.tablet),
                      SizedBox(width: 8),
                      Text('Tablet'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: PreviewMode.rectangle,
                    child: Row(children: [
                      Icon(Icons.crop_landscape),
                      SizedBox(width: 8),
                      Text('Retângulo'),
                    ]),
                  ),
                ],
              ),
            ),
            // Apply button
            Consumer<VisualEditorProvider>(
              builder: (_, p, __) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _hasUnappliedChanges
                    ? Padding(
                        key: const ValueKey(true),
                        padding: const EdgeInsets.only(right: 4),
                        child: FilledButton.tonal(
                          onPressed: () => _applyChanges(p),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 0),
                            minimumSize: const Size(0, 36),
                            textStyle: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Aplicar'),
                        ),
                      )
                    : const SizedBox.shrink(key: ValueKey(false)),
              ),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            // ── Canvas area ──────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Dot grid background
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _DotGridPainter(
                        cs.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  ),

                  // Canvas content
                  Consumer<VisualEditorProvider>(
                    builder: (_, p, __) {
                      if (!p.hasRoot) return const _EmptyCanvasHint();
                      return Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: GestureDetector(
                              onTap: () => p.deselect(),
                              child: _FramedNode(
                                node: p.root!,
                                provider: p,
                                mode: p.previewMode,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // Selected widget floating label
                  Consumer<VisualEditorProvider>(
                    builder: (_, p, __) {
                      final sel = p.selectedNode;
                      if (sel == null) return const SizedBox.shrink();
                      return Positioned(
                        top: 8,
                        left: 8,
                        child: Material(
                          elevation: 2,
                          borderRadius: BorderRadius.circular(20),
                          color: cs.primaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.widgets_outlined,
                                  size: 14,
                                  color: cs.onPrimaryContainer,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  sel.type,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onPrimaryContainer,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => p.deselect(),
                                  child: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: cs.onPrimaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),

            // ── Bottom panel ─────────────────────────────────────────────────
            _BottomPanel(
              originalSource: _originalSource,
              onApply: _applyChanges,
            ),

            // ── Bottom navigation bar ─────────────────────────────────────
            Consumer<VisualEditorProvider>(
              builder: (_, p, __) => NavigationBar(
                selectedIndex: p.activeTabIndex,
                onDestinationSelected: p.setActiveTab,
                height: 60,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.widgets_outlined),
                    label: 'Paleta',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.account_tree_outlined),
                    label: 'Árvore',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.tune_outlined),
                    label: 'Propriedades',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Empty canvas hint ─────────────────────────────────────────────────────────

class _EmptyCanvasHint extends StatelessWidget {
  const _EmptyCanvasHint();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.widgets_outlined,
            size: 52,
            color: cs.outlineVariant,
          ),
          const SizedBox(height: 14),
          Text(
            'Selecione a aba Paleta e\nadicione widgets ao canvas',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Bottom panel (resizable) ──────────────────────────────────────────────────

class _BottomPanel extends StatefulWidget {
  final String originalSource;
  final void Function(VisualEditorProvider) onApply;

  const _BottomPanel({
    required this.originalSource,
    required this.onApply,
  });

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  double _height = 220.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxH = MediaQuery.of(context).size.height * 0.48;

    return Consumer<VisualEditorProvider>(
      builder: (_, provider, __) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: _height,
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.07),
                blurRadius: 8,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: (d) {
                  setState(() {
                    _height =
                        (_height - d.delta.dy).clamp(80.0, maxH);
                  });
                },
                child: SizedBox(
                  height: 22,
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),

              // Content area
              Expanded(
                child: _buildTabContent(provider, cs),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabContent(VisualEditorProvider provider, ColorScheme cs) {
    switch (provider.activeTabIndex) {
      case 0:
        return _PalettePanel(provider: provider);
      case 1:
        return _TreePanel(provider: provider);
      case 2:
        return _PropertiesPanel(provider: provider);
      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Palette panel (bottom) ────────────────────────────────────────────────────

class _PalettePanel extends StatefulWidget {
  final VisualEditorProvider provider;

  const _PalettePanel({required this.provider});

  @override
  State<_PalettePanel> createState() => _PalettePanelState();
}

class _PalettePanelState extends State<_PalettePanel> {
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

    return Column(
      children: [
        // Search
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
          child: TextField(
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Pesquisar widgets…',
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

        // Drag hint
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              Icon(Icons.touch_app_rounded, size: 12, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                'Toque para adicionar · Segure para arrastar',
                style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
              ),
            ],
          ),
        ),

        // Category chips
        if (_search.isEmpty)
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _CatChip(
                  label: 'Todos',
                  selected: _selectedCategory == null,
                  onTap: () => setState(() => _selectedCategory = null),
                ),
                for (final cat in kWidgetCategories)
                  _CatChip(
                    label: cat,
                    selected: _selectedCategory == cat,
                    onTap: () => setState(() => _selectedCategory = cat),
                  ),
              ],
            ),
          ),

        const SizedBox(height: 4),

        // Widget list
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            itemCount: filtered.length,
            itemBuilder: (ctx, i) => _PaletteTile(
              def: filtered[i],
              provider: widget.provider,
            ),
          ),
        ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: selected
                ? cs.primaryContainer
                : cs.surfaceContainerHighest.withValues(alpha: 0.5),
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

class _PaletteTile extends StatelessWidget {
  final FlutterWidgetDef def;
  final VisualEditorProvider provider;

  const _PaletteTile({required this.def, required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final tileBody = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(def.icon, size: 18, color: def.color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              def.name,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurface),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: def.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              def.category,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: def.color),
            ),
          ),
        ],
      ),
    );

    final dragFeedback = Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: def.color.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 12, offset: const Offset(0, 4))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(def.icon, size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Text(def.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, fontFamily: 'monospace')),
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: LongPressDraggable<FlutterWidgetDef>(
        data: def,
        feedback: dragFeedback,
        childWhenDragging: Opacity(opacity: 0.35, child: tileBody),
        delay: const Duration(milliseconds: 200),
        child: InkWell(
          onTap: () {
            provider.addWidget(
              WidgetNode(
                type: def.name,
                properties: Map<String, dynamic>.from(def.defaultProperties),
              ),
            );
          },
          borderRadius: BorderRadius.circular(10),
          child: tileBody,
        ),
      ),
    );
  }
}

// ── Tree panel (bottom) ───────────────────────────────────────────────────────

class _TreePanel extends StatelessWidget {
  final VisualEditorProvider provider;

  const _TreePanel({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (provider.root == null) {
      return Center(
        child: Text(
          'Canvas vazio',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      children: [
        _TreeItem(node: provider.root!, provider: provider, depth: 0),
      ],
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
    final hasChildren = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () {
            provider.select(node.id);
            provider.setActiveTab(2);
          },
          child: Container(
            margin: EdgeInsets.only(left: depth * 14.0, bottom: 3),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.14)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? color.withValues(alpha: 0.5)
                    : cs.outlineVariant.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                if (def != null) ...[
                  Icon(def.icon, size: 14, color: color),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    node.type,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? color : cs.onSurface,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (hasChildren) ...[
                  Text(
                    '${node.children.length}',
                    style:
                        TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                ],
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => provider.removeWidget(node.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
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

// ── Embedded properties panel (bottom, tab 2) ─────────────────────────────────

class _PropertiesPanel extends StatefulWidget {
  final VisualEditorProvider provider;

  const _PropertiesPanel({required this.provider});

  @override
  State<_PropertiesPanel> createState() => _PropertiesPanelState();
}

class _PropertiesPanelState extends State<_PropertiesPanel> {
  void _set(String key, dynamic value) {
    final node = widget.provider.selectedNode;
    if (node == null) return;
    widget.provider.updateProperty(node.id, key, value);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = widget.provider;
    final node = provider.selectedNode;

    if (node == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Selecione um widget para ver as propriedades',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
        ),
      );
    }

    final props = _propsForType(node.type);

    return Column(
      children: [
        // Header: type badge + delete button
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    size: 18, color: cs.error),
                tooltip: 'Remover widget',
                onPressed: () {
                  provider.removeWidget(node.id);
                  provider.deselect();
                },
                style: IconButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  padding: const EdgeInsets.all(6),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                tooltip: 'Abrir no painel completo',
                onPressed: () {
                  showWidgetPropertiesSheet(
                    context: context,
                    node: node,
                    provider: provider,
                  );
                },
                style: IconButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // Property editors
        Expanded(
          child: props.isEmpty
              ? Center(
                  child: Text(
                    'Sem propriedades editáveis',
                    style: TextStyle(
                        color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
                  children: [
                    for (final prop in props)
                      _buildPropEditor(prop, node, cs),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildPropEditor(
      _PropDef prop, WidgetNode node, ColorScheme cs) {
    final current =
        node.properties[prop.key]?.toString() ?? '';

    switch (prop.type) {
      case _PT.text:
        return _TextPropField(
          label: prop.label,
          initial:
              current.isNotEmpty ? current : prop.defaultValue ?? '',
          onChanged: (v) => _set(prop.key, v.isEmpty ? null : v),
        );

      case _PT.number:
        return _TextPropField(
          label: prop.label,
          initial:
              current.isNotEmpty ? current : prop.defaultValue ?? '',
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
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
          current: current.isNotEmpty
              ? current
              : (prop.options?.first ?? ''),
          options: prop.options ?? [],
          onChanged: (v) => _set(prop.key, v),
          cs: cs,
        );

      case _PT.icon:
        return _IconPropPicker(
          label: prop.label,
          current: current.isNotEmpty
              ? current
              : (prop.defaultValue ?? 'Icons.star'),
          onSelected: (v) => _set(prop.key, v),
          cs: cs,
        );
    }
  }
}

// ── Prop editors (local copies, kept private to this file) ────────────────────

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
      padding: const EdgeInsets.only(bottom: 10),
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
          border:
              OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor:
              cs.surfaceContainerHighest.withValues(alpha: 0.4),
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
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
                      color:
                          selected ? cs.primary : cs.outlineVariant,
                      width: selected ? 2.5 : 1,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: cs.primary.withValues(alpha: 0.5),
                              blurRadius: 6,
                            )
                          ]
                        : null,
                  ),
                  child: selected
                      ? Icon(
                          Icons.check,
                          size: 14,
                          color: c.$2.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white,
                        )
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
    final safeValue =
        options.contains(current) ? current : options.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        value: safeValue,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 12),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor:
              cs.surfaceContainerHighest.withValues(alpha: 0.4),
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
      padding: const EdgeInsets.only(bottom: 10),
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
                        : cs.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected
                          ? cs.primary
                          : cs.outlineVariant
                              .withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    ico.$2,
                    size: 18,
                    color:
                        selected ? cs.primary : cs.onSurfaceVariant,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ── Property definitions (local copy) ─────────────────────────────────────────

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
        _PropDef('mainAxisAlignment', 'Main Axis Alignment',
            _PT.dropdown,
            options: mainAxisOptions,
            defaultValue: 'MainAxisAlignment.start'),
        _PropDef('crossAxisAlignment', 'Cross Axis Alignment',
            _PT.dropdown,
            options: crossAxisOptions,
            defaultValue: 'CrossAxisAlignment.center'),
      ];

    case 'Stack':
      return [
        _PropDef('alignment', 'Alinhamento', _PT.dropdown,
            options: alignmentOptions,
            defaultValue: 'Alignment.topLeft'),
      ];

    case 'Wrap':
      return [
        _PropDef('spacing', 'Espaçamento', _PT.number,
            defaultValue: '8.0'),
        _PropDef('runSpacing', 'Run Spacing', _PT.number,
            defaultValue: '8.0'),
      ];

    case 'Container':
      return [
        _PropDef('width', 'Largura', _PT.number),
        _PropDef('height', 'Altura', _PT.number),
        _PropDef('color', 'Cor', _PT.color),
        _PropDef('borderRadius', 'Border Radius', _PT.number),
        _PropDef('padding', 'Padding (todos)', _PT.number),
      ];

    case 'Padding':
      return [
        _PropDef('padding', 'Padding (todos)', _PT.number,
            defaultValue: '8.0')
      ];

    case 'Align':
      return [
        _PropDef('alignment', 'Alinhamento', _PT.dropdown,
            options: alignmentOptions,
            defaultValue: 'Alignment.center'),
      ];

    case 'Expanded':
    case 'Flexible':
      return [
        _PropDef('flex', 'Flex', _PT.number, defaultValue: '1')
      ];

    case 'SizedBox':
      return [
        _PropDef('width', 'Largura', _PT.number),
        _PropDef('height', 'Altura', _PT.number),
      ];

    case 'Card':
      return [
        _PropDef('elevation', 'Elevação', _PT.number,
            defaultValue: '2.0')
      ];

    case 'ClipRRect':
      return [
        _PropDef('borderRadius', 'Border Radius', _PT.number,
            defaultValue: '8.0')
      ];

    case 'Opacity':
      return [
        _PropDef('opacity', 'Opacidade (0-1)', _PT.number,
            defaultValue: '1.0')
      ];

    case 'Text':
      return [
        _PropDef('text', 'Texto', _PT.text,
            defaultValue: 'Hello World'),
        _PropDef('fontSize', 'Tamanho da fonte', _PT.number),
        _PropDef('fontWeight', 'Peso da fonte', _PT.dropdown,
            options: fontWeightOptions),
        _PropDef('color', 'Cor', _PT.color),
      ];

    case 'Icon':
      return [
        _PropDef('icon', 'Ícone', _PT.icon,
            defaultValue: 'Icons.star'),
        _PropDef('size', 'Tamanho', _PT.number, defaultValue: '24.0'),
        _PropDef('color', 'Cor', _PT.color),
      ];

    case 'Image':
      return [
        _PropDef('url', 'URL da imagem', _PT.text),
        _PropDef('fit', 'Fit', _PT.dropdown,
            options: fitOptions, defaultValue: 'BoxFit.cover'),
      ];

    case 'FlutterLogo':
      return [
        _PropDef('size', 'Tamanho', _PT.number, defaultValue: '48.0')
      ];

    case 'CircleAvatar':
      return [
        _PropDef('radius', 'Raio', _PT.number, defaultValue: '24.0'),
        _PropDef('backgroundColor', 'Cor de fundo', _PT.color),
      ];

    case 'ElevatedButton':
    case 'TextButton':
    case 'OutlinedButton':
    case 'FilledButton':
      return [
        _PropDef('label', 'Rótulo', _PT.text, defaultValue: 'Botão')
      ];

    case 'IconButton':
    case 'FloatingActionButton':
      return [
        _PropDef('icon', 'Ícone', _PT.icon, defaultValue: 'Icons.add')
      ];

    case 'TextField':
      return [
        _PropDef('hintText', 'Texto de dica', _PT.text),
        _PropDef('labelText', 'Rótulo', _PT.text),
      ];

    case 'Slider':
      return [
        _PropDef('value', 'Valor inicial (0-1)', _PT.number,
            defaultValue: '0.5')
      ];

    case 'Chip':
    case 'Badge':
      return [
        _PropDef('label', 'Rótulo', _PT.text, defaultValue: 'Label')
      ];

    case 'ListTile':
      return [
        _PropDef('title', 'Título', _PT.text, defaultValue: 'Título'),
        _PropDef('subtitle', 'Subtítulo', _PT.text),
      ];

    case 'AppBar':
    case 'Scaffold':
      return [
        _PropDef('appBarTitle', 'Título do AppBar', _PT.text,
            defaultValue: 'AppBar')
      ];

    case 'Tooltip':
      return [
        _PropDef('message', 'Mensagem', _PT.text,
            defaultValue: 'Tooltip')
      ];

    case 'Spacer':
      return [
        _PropDef('flex', 'Flex', _PT.number, defaultValue: '1')
      ];

    case 'Material':
      return [_PropDef('color', 'Cor', _PT.color)];

    default:
      return [];
  }
}

// ── Framed node (device frame + widget preview) ───────────────────────────────

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
    final screenContent = _safeRender(node, context);

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
                color: cs.outline.withValues(alpha: 0.55),
                radius: r,
              ),
            ),
          ),
          // Notch indicator
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

  Widget _safeRender(WidgetNode n, BuildContext context) {
    return MediaQuery(
      data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 1.0),
      child: Material(
        type: MaterialType.canvas,
        color: Colors.white,
        child: RfwRenderer(root: n),
      ),
    );
  }
}

// ── Preview mode icon helper ──────────────────────────────────────────────────

IconData _modeIcon(PreviewMode mode) {
  switch (mode) {
    case PreviewMode.phone:
      return Icons.smartphone;
    case PreviewMode.tablet:
      return Icons.tablet;
    case PreviewMode.rectangle:
      return Icons.crop_landscape;
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
        Radius.circular(radius),
      ),
      paint,
    );
    // Home indicator bar
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
