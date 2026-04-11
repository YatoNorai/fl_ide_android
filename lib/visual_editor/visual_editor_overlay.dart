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
/// Returns without navigating when the active file is not a Flutter widget.
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
    return; // Do not open the editor when validation fails
  }

  // Capture references before pushing so the callback always targets the
  // correct file even if the user switches tabs inside the overlay.
  final capturedFile = file!;
  void onCodeChanged(String newSource) {
    capturedFile.controller?.setText(newSource);
    ep.markDirty();
  }

  Navigator.of(context).push(
    PageRouteBuilder(
      pageBuilder: (_, __, ___) => VisualEditorOverlay(
        initialNode: initialNode,
        sourcePath: sourcePath,
        originalSource: originalSource,
        onCodeChanged: onCodeChanged,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut, reverseCurve: Curves.easeIn),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 220),
    ),
  );
}

class VisualEditorOverlay extends StatelessWidget {
  final WidgetNode? initialNode;
  final String? sourcePath;
  final String originalSource;
  final String? parseError;
  /// Called whenever the widget tree changes so the code editor stays in sync.
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
        parseError: parseError,
        onCodeChanged: onCodeChanged,
      ),
    );
  }
}

// ── Main body ─────────────────────────────────────────────────────────────────

class _VisualEditorBody extends StatefulWidget {
  final String? sourcePath;
  final String originalSource;
  final String? parseError;
  final void Function(String newSource)? onCodeChanged;

  const _VisualEditorBody({
    this.sourcePath,
    this.originalSource = '',
    this.parseError,
    this.onCodeChanged,
  });

  @override
  State<_VisualEditorBody> createState() => _VisualEditorBodyState();
}

class _VisualEditorBodyState extends State<_VisualEditorBody> {
  final _transformCtrl = TransformationController();
  late VisualEditorProvider _editorProvider;
  bool _listenerAttached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_listenerAttached) {
      _editorProvider = context.read<VisualEditorProvider>();
      _editorProvider.addListener(_syncToEditor);
      _listenerAttached = true;
    }
  }

  @override
  void dispose() {
    if (_listenerAttached) _editorProvider.removeListener(_syncToEditor);
    _transformCtrl.dispose();
    super.dispose();
  }

  /// Regenerates the Dart source from the current tree and pushes it to
  /// the code editor controller so the two views stay in sync automatically.
  void _syncToEditor() {
    final cb = widget.onCodeChanged;
    if (cb == null) return;
    final code = _editorProvider.generateCode();
    if (code.isEmpty) return;
    final newSource = widget.originalSource.isNotEmpty
        ? DartWidgetParser().replaceReturnInBuild(widget.originalSource, code)
        : _editorProvider.generateFullCode();
    cb(newSource);
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openPalette(VisualEditorProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PaletteBottomSheet(provider: provider),
    );
  }

  void _openTree(VisualEditorProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TreeBottomSheet(provider: provider),
    );
  }

  void _showCode(VisualEditorProvider provider) {
    final code = provider.generateFullCode();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Canvas está vazio')),
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

  Future<void> _saveToFile(VisualEditorProvider provider) async {
    if (widget.sourcePath == null) return;
    final widgetCode = provider.generateCode();
    if (widgetCode.isEmpty) return;

    final newSource = widget.originalSource.isNotEmpty
        ? DartWidgetParser().replaceReturnInBuild(widget.originalSource, widgetCode)
        : provider.generateFullCode();

    try {
      await File(widget.sourcePath!).writeAsString(newSource);
      // Ensure the in-memory editor controller matches what's on disk.
      widget.onCodeChanged?.call(newSource);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Salvo em ${widget.sourcePath!.split('/').last.split('\\').last}',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmClear(VisualEditorProvider provider) {
    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar canvas?'),
        content: const Text('Todos os widgets serão removidos.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Limpar'),
          ),
        ],
      ),
    ).then((ok) {
      if (ok == true) provider.clearRoot();
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final provider = context.watch<VisualEditorProvider>();

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness:
            Theme.of(context).brightness == Brightness.dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: cs.surface,
      ),
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLowest,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: SafeArea(
            bottom: false,
            child: _TopBar(
              provider: provider,
              sourcePath: widget.sourcePath,
              onCode: () => _showCode(provider),
              onTree: () => _openTree(provider),
              onSave: () => _saveToFile(provider),
              onClear: () => _confirmClear(provider),
            ),
          ),
        ),
        body: Stack(
          children: [
            // ── Pannable / zoomable canvas ──────────────────────────────────
            Positioned.fill(
              child: InteractiveViewer(
                transformationController: _transformCtrl,
                minScale: 0.2,
                maxScale: 4.0,
                child: _CanvasArea(
                  provider: provider,
                  parseError: widget.parseError,
                ),
              ),
            ),

            // ── Reset zoom pill (top-right, visible only when tree exists) ──
            Positioned(
              top: 8,
              right: 8,
              child: AnimatedOpacity(
                opacity: provider.hasRoot ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: _ZoomResetButton(ctrl: _transformCtrl, cs: cs),
              ),
            ),

            // ── Selection bar (slides up from bottom) ───────────────────────
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _SelectionBar(
                provider: provider,
                onProperties: () {
                  final node = provider.selectedNode;
                  if (node != null) {
                    showWidgetPropertiesSheet(
                      context: context,
                      node: node,
                      provider: provider,
                    );
                  }
                },
              ),
            ),
          ],
        ),

        // ── FAB: add widget ─────────────────────────────────────────────────
        floatingActionButton: AnimatedPadding(
          // Lift FAB above the selection bar when it's visible
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            bottom: provider.selectedNode != null ? 64 : 0,
          ),
          child: FloatingActionButton(
            onPressed: () => _openPalette(provider),
            tooltip: 'Adicionar widget',
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

enum _OverflowAction { tree, save, clear }

class _TopBar extends StatelessWidget {
  final VisualEditorProvider provider;
  final String? sourcePath;
  final VoidCallback onCode;
  final VoidCallback onTree;
  final VoidCallback onSave;
  final VoidCallback onClear;

  const _TopBar({
    required this.provider,
    required this.onCode,
    required this.onTree,
    required this.onSave,
    required this.onClear,
    this.sourcePath,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      height: kToolbarHeight,
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          // Back
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
            onPressed: () => Navigator.of(context).pop(),
          ),

          // Title
          Text(
            'Visual Editor',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),

          const Spacer(),

          // Frame mode
          IconButton(
            icon: Icon(_frameIcon(provider.previewMode), size: 20),
            color: cs.tertiary,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Alternar frame',
            onPressed: () => _cycleFrame(provider),
          ),

          // Generated code
          IconButton(
            icon: const Icon(Icons.code_rounded, size: 20),
            color: cs.onSurfaceVariant,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            tooltip: 'Ver código',
            onPressed: onCode,
          ),

          // Overflow menu
          PopupMenuButton<_OverflowAction>(
            icon: Icon(Icons.more_vert_rounded, size: 20, color: cs.onSurfaceVariant),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            padding: EdgeInsets.zero,
            onSelected: (action) {
              switch (action) {
                case _OverflowAction.tree:
                  onTree();
                case _OverflowAction.save:
                  onSave();
                case _OverflowAction.clear:
                  onClear();
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: _OverflowAction.tree,
                child: _MenuRow(
                  icon: Icons.account_tree_outlined,
                  label: 'Árvore de widgets',
                ),
              ),
              if (provider.hasRoot && sourcePath != null)
                const PopupMenuItem(
                  value: _OverflowAction.save,
                  child: _MenuRow(
                    icon: Icons.save_outlined,
                    label: 'Salvar no arquivo',
                  ),
                ),
              if (provider.hasRoot)
                const PopupMenuItem(
                  value: _OverflowAction.clear,
                  child: _MenuRow(
                    icon: Icons.delete_sweep_outlined,
                    label: 'Limpar canvas',
                    color: Colors.red,
                  ),
                ),
            ],
          ),

          const SizedBox(width: 4),
        ],
      ),
    );
  }

  IconData _frameIcon(PreviewMode mode) => switch (mode) {
    PreviewMode.rectangle => Icons.crop_landscape_rounded,
    PreviewMode.phone     => Icons.phone_android_rounded,
    PreviewMode.tablet    => Icons.tablet_android_rounded,
  };

  void _cycleFrame(VisualEditorProvider p) {
    final values = PreviewMode.values;
    p.setPreviewMode(values[(values.indexOf(p.previewMode) + 1) % values.length]);
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: c),
        const SizedBox(width: 12),
        Text(label, style: TextStyle(fontSize: 13, color: c)),
      ],
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

    return GestureDetector(
      onTap: () => provider.deselect(),
      child: Container(
        color: cs.surfaceContainerLowest,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dot-grid background
            CustomPaint(
              painter: _DotGridPainter(cs.outlineVariant.withValues(alpha: 0.35)),
            ),

            // Empty state
            if (!provider.hasRoot)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      parseError != null ? Icons.error_outline : Icons.widgets_outlined,
                      size: 52,
                      color: parseError != null ? cs.error : cs.outlineVariant,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      parseError ?? 'Toque em  +  para adicionar widgets',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: parseError != null ? cs.error : cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),

            // Widget preview inside device frame
            if (provider.hasRoot)
              Center(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 96),
                  child: _FramedNode(
                    node: provider.root!,
                    provider: provider,
                    mode: provider.previewMode,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Zoom reset pill ───────────────────────────────────────────────────────────

class _ZoomResetButton extends StatelessWidget {
  final TransformationController ctrl;
  final ColorScheme cs;

  const _ZoomResetButton({required this.ctrl, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: cs.surfaceContainerHigh.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(10),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => ctrl.value = Matrix4.identity(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fit_screen_rounded, size: 15, color: cs.onSurface),
              const SizedBox(width: 4),
              Text(
                '1:1',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Selection bar (bottom) ────────────────────────────────────────────────────

class _SelectionBar extends StatelessWidget {
  final VisualEditorProvider provider;
  final VoidCallback onProperties;

  const _SelectionBar({required this.provider, required this.onProperties});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final node = provider.selectedNode;
    final def = node != null ? defForType(node.type) : null;

    return AnimatedSlide(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      offset: node != null ? Offset.zero : const Offset(0, 1),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: node != null ? 1.0 : 0.0,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              if (node != null) ...[
                Icon(
                  def?.icon ?? Icons.widgets_outlined,
                  size: 16,
                  color: def?.color ?? cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    node.type,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Delete selected node
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: cs.error),
                  tooltip: 'Remover widget',
                  onPressed: () => provider.removeWidget(node.id),
                  style: IconButton.styleFrom(
                    minimumSize: const Size(36, 36),
                    padding: const EdgeInsets.all(6),
                  ),
                ),
                const SizedBox(width: 4),
                // Open properties
                FilledButton.tonal(
                  onPressed: onProperties,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    minimumSize: const Size(0, 36),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: const Text('Propriedades'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Palette bottom sheet ──────────────────────────────────────────────────────

class _PaletteBottomSheet extends StatefulWidget {
  final VisualEditorProvider provider;

  const _PaletteBottomSheet({required this.provider});

  @override
  State<_PaletteBottomSheet> createState() => _PaletteBottomSheetState();
}

class _PaletteBottomSheetState extends State<_PaletteBottomSheet> {
  String _search = '';
  String? _selectedCategory;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final filtered = kFlutterWidgets.where((w) {
      final matchSearch = _search.isEmpty ||
          w.name.toLowerCase().contains(_search.toLowerCase());
      final matchCat = _selectedCategory == null || w.category == _selectedCategory;
      return matchSearch && matchCat;
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.52,
      minChildSize: 0.28,
      maxChildSize: 0.88,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Text(
                      'Adicionar Widget',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ),

              // Search field
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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

              // Category chips
              if (_search.isEmpty)
                SizedBox(
                  height: 34,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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

              const SizedBox(height: 6),

              // Widget list
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: filtered.length,
                  itemBuilder: (ctx2, i) => _PaletteTile(
                    def: filtered[i],
                    provider: widget.provider,
                    onAdded: () => Navigator.pop(ctx),
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

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CatChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
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
  final VoidCallback onAdded;

  const _PaletteTile({
    required this.def,
    required this.provider,
    required this.onAdded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: () {
          provider.addWidget(
            WidgetNode(
              type: def.name,
              properties: Map<String, dynamic>.from(def.defaultProperties),
            ),
          );
          onAdded();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      def.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: def.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  def.category,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: def.color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tree bottom sheet ─────────────────────────────────────────────────────────

class _TreeBottomSheet extends StatelessWidget {
  final VisualEditorProvider provider;

  const _TreeBottomSheet({required this.provider});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                child: Row(
                  children: [
                    Icon(Icons.account_tree_outlined, size: 18, color: cs.secondary),
                    const SizedBox(width: 8),
                    Text(
                      'Árvore de Widgets',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Tree content
              Expanded(
                child: provider.root == null
                    ? Center(
                        child: Text(
                          'Canvas vazio',
                          style: TextStyle(color: cs.outlineVariant, fontSize: 13),
                        ),
                      )
                    : ListView(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        children: [
                          _TreeItem(
                            node: provider.root!,
                            provider: provider,
                            depth: 0,
                          ),
                        ],
                      ),
              ),
            ],
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
    final screenContent = _safeRender(node);

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
      return MediaQuery(
        data: const MediaQueryData(size: Size(390, 844), devicePixelRatio: 1.0),
        child: Material(
          type: MaterialType.canvas,
          color: Colors.white,
          child: WidgetRenderer.render(n),
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

// ── Widget tree recursive items ───────────────────────────────────────────────

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
          onTap: () => provider.select(node.id),
          child: Container(
            margin: EdgeInsets.only(left: depth * 14.0, bottom: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
                    style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 4),
                ],
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => provider.removeWidget(node.id),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        size: 13,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
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
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Código Gerado',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface,
                      ),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: code));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Código copiado!')),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copiar'),
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
          Rect.fromLTWH(0, 0, size.width, size.height), Radius.circular(radius)),
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
  bool shouldRepaint(_DevicePainter old) => old.color != color || old.radius != radius;
}
