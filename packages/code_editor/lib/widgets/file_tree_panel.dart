import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart' show FileNode, showThemedDialog;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ssh_pkg/ssh_pkg.dart';

import '../providers/editor_provider.dart';

/// Returns true when [path] belongs to a project hosted on the SSH remote.
bool _isRemote(BuildContext ctx, String path) {
  try {
    final ssh = ctx.read<SshProvider>();
    final rp = ssh.config?.remoteProjectsPath ?? '';
    return ssh.isConnected && rp.isNotEmpty && path.startsWith(rp);
  } catch (_) {
    return false;
  }
}

// ── Blur bottom sheet ─────────────────────────────────────────────────────────

Future<T?> _showBlurredSheet<T>(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    isScrollControlled: true,
    builder: (ctx) => Stack(
      children: [
        // Detector de toque na área do Blur
        Positioned.fill(
          child: GestureDetector(
            onTap: () => Navigator.pop(ctx), // Fecha o sheet
            behavior: HitTestBehavior.opaque, // Garante que detecte o toque mesmo sendo "vazio"
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                color: Colors.black.withOpacity(0.1), // Um leve tom para ajudar no contraste
              ),
            ),
          ),
        ),
        // Conteúdo do Sheet
        Align(
          alignment: Alignment.bottomCenter,
          child: CustomPaint(
            painter: _TopRoundedBorderPainter(
              color: Colors.grey,
              width: 0.5,
              radius: 20.0,
            ),
            child: Container(
              // Importante: BoxDecoration e BorderRadius aqui
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                child: builder(ctx),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

// Classe auxiliar para desenhar a borda seguindo a curva
class _TopRoundedBorderPainter extends CustomPainter {
  final Color color;
  final double width;
  final double radius;

  _TopRoundedBorderPainter({
    required this.color, 
    required this.width, 
    required this.radius
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round // Arredonda a ponta inicial e final da linha
      ..strokeJoin = StrokeJoin.round; // Suaviza a conexão entre reta e curva

    final path = Path();
    
    // Começamos um pouco abaixo do início da curva na lateral esquerda
    // para garantir que a curva seja desenhada por completo.
    path.moveTo(0, radius); 
    
    // Desenha a curva superior esquerda
    path.arcToPoint(
      Offset(radius, 0),
      radius: Radius.circular(radius),
      clockwise: true,
    );

    // Linha reta do topo
    path.lineTo(size.width - radius, 0);

    // Desenha a curva superior direita
    path.arcToPoint(
      Offset(size.width, radius),
      radius: Radius.circular(radius),
      clockwise: true,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
class FileTreePanel extends StatelessWidget {
  final VoidCallback? onFileSelected;
  /// Called when the user taps an APK file — workspace_screen shows the
  /// install dialog using this callback instead of opening the file in editor.
  final void Function(String apkPath)? onApkTap;
  final bool liquidGlass;
  const FileTreePanel({super.key, this.onFileSelected, this.onApkTap, this.liquidGlass = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // Rebuild when rootNode changes (project open/close) OR when treeVersion
    // increments (folder expanded/collapsed). The version counter is needed
    // because expandNode() mutates the existing FileNode in place — the rootNode
    // reference doesn't change, so a plain rootNode select would miss it.
    // Active-file highlighting is handled per-leaf via context.select<>.
    final (rootNode, _) = context.select<EditorProvider, (FileNode?, int)>(
      (e) => (e.rootNode, e.treeVersion),
    );
    return ColoredBox(
      color: liquidGlass ? Colors.transparent : cs.surface,
      child: rootNode == null
          ? Center(
              child: Text('No project open',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14)),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: _FileTreeNode(
                node: rootNode,
                depth: 0,
                onFileSelected: onFileSelected,
                onApkTap: onApkTap,
              ),
            ),
    );
  }
}

// ── Tree routing ──────────────────────────────────────────────────────────────

class _FileTreeNode extends StatelessWidget {
  final FileNode node;
  final int depth;
  final VoidCallback? onFileSelected;
  final void Function(String apkPath)? onApkTap;
  const _FileTreeNode(
      {super.key, required this.node, required this.depth,
       this.onFileSelected, this.onApkTap});

  @override
  Widget build(BuildContext context) => node.isDirectory
      ? _DirectoryNode(
          node: node, depth: depth,
          onFileSelected: onFileSelected, onApkTap: onApkTap)
      : _FileLeaf(
          node: node, depth: depth,
          onFileSelected: onFileSelected, onApkTap: onApkTap);
}

// ── Directory node ────────────────────────────────────────────────────────────

class _DirectoryNode extends StatefulWidget {
  final FileNode node;
  final int depth;
  final VoidCallback? onFileSelected;
  final void Function(String apkPath)? onApkTap;
  const _DirectoryNode(
      {required this.node, required this.depth,
       this.onFileSelected, this.onApkTap});

  @override
  State<_DirectoryNode> createState() => _DirectoryNodeState();
}

class _DirectoryNodeState extends State<_DirectoryNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;
  // Track expanded state separately: node is mutated in-place, so
  // oldWidget.node.isExpanded == widget.node.isExpanded in didUpdateWidget.
  late bool _isExpanded;
  // Whether children should still be in the tree (true while animating collapse).
  bool _showChildren = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.node.isExpanded;
    _showChildren = _isExpanded;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: _isExpanded ? 1.0 : 0.0,
    );
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
    _ctrl.addStatusListener(_onStatus);
  }

  @override
  void didUpdateWidget(_DirectoryNode old) {
    super.didUpdateWidget(old);
    final nowExpanded = widget.node.isExpanded;
    if (nowExpanded == _isExpanded) return;
    _isExpanded = nowExpanded;
    if (nowExpanded) {
      setState(() => _showChildren = true);
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      setState(() => _showChildren = false);
    }
  }

  @override
  void dispose() {
    _ctrl.removeStatusListener(_onStatus);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TreeItem(
          node: widget.node,
          depth: widget.depth,
          leading: RotationTransition(
            turns: Tween<double>(begin: 0.0, end: 0.25).animate(_anim),
            child: Icon(Icons.arrow_right_rounded, size: 20,
                color: cs.onSurfaceVariant),
          ),
          icon: Icons.folder_rounded,
          iconColor: const Color(0xFF90B4E8),
          label: widget.node.name,
          onTap: () => context.read<EditorProvider>().expandNode(widget.node),
          onLongPress: () => _showDirSheet(context, widget.node),
        ),
        if (_showChildren)
          SizeTransition(
            sizeFactor: _anim,
            axisAlignment: -1.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.node.children.map((child) => _FileTreeNode(
                  key: ValueKey(child.path),
                  node: child,
                  depth: widget.depth + 1,
                  onFileSelected: widget.onFileSelected,
                  onApkTap: widget.onApkTap)).toList(),
            ),
          ),
      ],
    );
  }

  void _showDirSheet(BuildContext context, FileNode dir) {
    final editor = context.read<EditorProvider>();
    final parentCtx = context;
    _showBlurredSheet(
      context,
      (ctx) => _DirActionsSheet(
        dir: dir,
        parentContext: parentCtx,
        onRefresh: editor.refreshTree,
        onCloseUnder: (path) => editor.closeFilesUnderPath(path),
        onOpenFile: editor.openFile,
      ),
    );
  }
}

// ── File leaf ─────────────────────────────────────────────────────────────────

class _FileLeaf extends StatelessWidget {
  final FileNode node;
  final int depth;
  final VoidCallback? onFileSelected;
  final void Function(String apkPath)? onApkTap;
  const _FileLeaf(
      {required this.node, required this.depth,
       this.onFileSelected, this.onApkTap});

  bool get _isApk => node.extension.toLowerCase() == 'apk';

  @override
  Widget build(BuildContext context) {
    // select<> only rebuilds this leaf when the active file path changes,
    // not on every EditorProvider notification (tab reorder, dirty flag, etc.)
    final isActive = context.select<EditorProvider, bool>(
      (e) => e.activeFile?.path == node.path,
    );
    return _TreeItem(
      node: node,
      depth: depth,
      icon: _fileIcon(node.extension),
      iconColor: _fileIconColor(node.extension),
      label: node.name,
      isActive: isActive,
      onTap: () {
        if (_isApk) {
          onApkTap?.call(node.path);
        } else {
          // Images and text files both go through openFile — the editor area
          // will show the correct viewer based on file.isImage.
          // bringToFront: already-open files move to the first tab position.
          context.read<EditorProvider>().openFile(node.path, bringToFront: true);
          onFileSelected?.call();
        }
      },
      onLongPress: () => _showFileSheet(context, node),
    );
  }

  void _showFileSheet(BuildContext context, FileNode file) {
    final editor = context.read<EditorProvider>();
    final parentCtx = context;
    _showBlurredSheet(
      context,
      (ctx) => _FileActionsSheet(
        file: file,
        parentContext: parentCtx,
        onRefresh: editor.refreshTree,
        onInstallApk: _isApk ? () => onApkTap?.call(file.path) : null,
        onCloseFile: () {
          final idx =
              editor.openFiles.indexWhere((f) => f.path == file.path);
          if (idx != -1) editor.closeFile(idx);
        },
      ),
    );
  }

  IconData _fileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':     return Icons.flutter_dash;
      case 'yaml':
      case 'yml':      return Icons.settings_outlined;
      case 'json':     return Icons.data_object_outlined;
      case 'md':       return Icons.article_outlined;
      case 'kt':
      case 'kts':      return Icons.code;
      case 'java':     return Icons.coffee;
      case 'js':
      case 'mjs':      return Icons.javascript;
      case 'ts':
      case 'tsx':
      case 'jsx':      return Icons.code;
      case 'py':       return Icons.terminal;
      case 'xml':      return Icons.code;
      case 'html':     return Icons.html;
      case 'css':      return Icons.style_outlined;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'svg':      return Icons.image_outlined;
      case 'sh':
      case 'bash':     return Icons.terminal;
      case 'gradle':   return Icons.build_outlined;
      case 'bat':      return Icons.terminal;
      case 'apk':      return Icons.android_rounded;
      default:         return Icons.insert_drive_file_outlined;
    }
  }

  Color _fileIconColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'dart':     return const Color(0xFF54C5F8);
      case 'yaml':
      case 'yml':      return const Color(0xFFE8C96B);
      case 'json':     return const Color(0xFFABB2BF);
      case 'kt':
      case 'kts':      return const Color(0xFFA97BFF);
      case 'java':     return const Color(0xFFF0AB00);
      case 'js':
      case 'mjs':      return const Color(0xFFF7DF1E);
      case 'ts':
      case 'tsx':      return const Color(0xFF3178C6);
      case 'jsx':      return const Color(0xFF61DAFB);
      case 'py':       return const Color(0xFF3572A5);
      case 'html':     return const Color(0xFFE34C26);
      case 'xml':      return const Color(0xFFE4A600);
      case 'css':      return const Color(0xFF264DE4);
      case 'gradle':   return const Color(0xFF00C4BB);
      case 'sh':
      case 'bash':
      case 'bat':      return const Color(0xFF89DDFF);
      case 'md':       return const Color(0xFF9CA3AF);
      case 'apk':      return const Color(0xFF3DDC84); // Android green
      default:         return const Color(0xFF9CA3AF);
    }
  }
}

// ── Tree item (row widget) ────────────────────────────────────────────────────

class _TreeItem extends StatefulWidget {
  final FileNode node;
  final int depth;
  final Widget? leading;
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _TreeItem({
    required this.node,
    required this.depth,
    this.leading,
    required this.icon,
    required this.iconColor,
    required this.label,
    this.isActive = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_TreeItem> createState() => _TreeItemState();
}

class _TreeItemState extends State<_TreeItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Container(
          height: 36,
          padding:
              EdgeInsets.only(left: 8.0 + widget.depth * 16.0, right: 8),
          color: widget.isActive
              ? cs.primaryContainer
              : _hovered
                  ? cs.surfaceContainerHigh
                  : Colors.transparent,
          child: Row(
            children: [
              SizedBox(width: 22, child: widget.leading),
              const SizedBox(width: 6),
              Icon(widget.icon, size: 18, color: widget.iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    color: widget.isActive
                        ? cs.onPrimaryContainer
                        : cs.onSurface,
                    fontSize: 14,
                    fontWeight: widget.isActive
                        ? FontWeight.w500
                        : FontWeight.w400,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── File context sheet ────────────────────────────────────────────────────────

class _FileActionsSheet extends StatelessWidget {
  final FileNode file;
  final BuildContext parentContext;
  final VoidCallback onRefresh;
  final VoidCallback onCloseFile;
  /// Non-null only for APK files — calls onApkTap from the tree.
  final VoidCallback? onInstallApk;

  const _FileActionsSheet({
    required this.file,
    required this.parentContext,
    required this.onRefresh,
    required this.onCloseFile,
    this.onInstallApk,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isApk = file.extension.toLowerCase() == 'apk';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(
                  isApk ? Icons.android_rounded : Icons.insert_drive_file_outlined,
                  size: 16,
                  color: isApk ? const Color(0xFF3DDC84) : cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(file.name,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            if (isApk)
              _SheetAction(
                icon: Icons.install_mobile_rounded,
                label: 'Install APK',
                color: const Color(0xFF3DDC84),
                onTap: () {
                  Navigator.pop(context);
                  onInstallApk?.call();
                },
              ),
            _SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: cs.error,
              onTap: () => _confirmDelete(context),
            ),
            _SheetAction(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
              onTap: () => _showRename(context),
            ),
            _SheetAction(
              icon: Icons.copy_outlined,
              label: 'Copy path',
              onTap: () {
                Clipboard.setData(ClipboardData(text: file.path));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Path copied')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    Navigator.pop(context);
    showThemedDialog(
      context: parentContext,
      title: 'Delete file?',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text('Delete "${file.name}"? This cannot be undone.'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(parentContext),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(parentContext).colorScheme.error),
          onPressed: () async {
            Navigator.pop(parentContext);
            try {
              onCloseFile();
              if (_isRemote(parentContext, file.path)) {
                await parentContext.read<SshProvider>().deleteFile(file.path);
              } else {
                await File(file.path).delete();
              }
              onRefresh();
            } catch (e) {
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }

  void _showRename(BuildContext context) {
    Navigator.pop(context);
    final ctrl = TextEditingController(text: file.name);
    showThemedDialog(
      context: parentContext,
      title: 'Rename file',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(parentContext),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final newName = ctrl.text.trim();
            if (newName.isEmpty) return;
            Navigator.pop(parentContext);
            final sep = file.path.contains('/') ? '/' : r'\';
            final parent =
                file.path.substring(0, file.path.lastIndexOf(sep));
            try {
              if (_isRemote(parentContext, file.path)) {
                await parentContext
                    .read<SshProvider>()
                    .rename(file.path, '$parent/$newName');
              } else {
                await File(file.path).rename('$parent/$newName');
              }
              onRefresh();
            } catch (e) {
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

// ── Directory context sheet ───────────────────────────────────────────────────

class _DirActionsSheet extends StatelessWidget {
  final FileNode dir;
  final BuildContext parentContext;
  final VoidCallback onRefresh;
  final void Function(String path) onCloseUnder;
  final Future<void> Function(String path) onOpenFile;

  const _DirActionsSheet({
    required this.dir,
    required this.parentContext,
    required this.onRefresh,
    required this.onCloseUnder,
    required this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Icon(Icons.folder_rounded,
                    size: 16, color: const Color(0xFF90B4E8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(dir.name,
                      style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                ),
              ]),
            ),
            const SizedBox(height: 4),
            _SheetAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              color: cs.error,
              onTap: () => _confirmDelete(context),
            ),
            _SheetAction(
              icon: Icons.note_add_outlined,
              label: 'New file',
              onTap: () => _showNewItem(context, isFile: true),
            ),
            _SheetAction(
              icon: Icons.create_new_folder_outlined,
              label: 'New folder',
              onTap: () => _showNewItem(context, isFile: false),
            ),
            _SheetAction(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
              onTap: () => _showRename(context),
            ),
            _SheetAction(
              icon: Icons.add_photo_alternate_outlined,
              label: 'Importar imagem',
              onTap: () => _importImages(context),
            ),
            _SheetAction(
              icon: Icons.copy_outlined,
              label: 'Copy path',
              onTap: () {
                Clipboard.setData(ClipboardData(text: dir.path));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Path copied')));
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _importImages(BuildContext context) async {
    Navigator.pop(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return;

    final errors = <String>[];
    for (final f in result.files) {
      final srcPath = f.path;
      if (srcPath == null) continue;
      final dest = '${dir.path}/${f.name}';
      try {
        await File(srcPath).copy(dest);
      } catch (e) {
        errors.add(f.name);
      }
    }

    onRefresh();

    if (parentContext.mounted) {
      if (errors.isEmpty) {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(content: Text(
            result.files.length == 1
                ? 'Imagem importada com sucesso'
                : '${result.files.length} imagens importadas',
          )),
        );
      } else {
        ScaffoldMessenger.of(parentContext).showSnackBar(
          SnackBar(content: Text('Erro ao importar: ${errors.join(', ')}')),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context) {
    Navigator.pop(context);
    showThemedDialog(
      context: parentContext,
      title: 'Delete folder?',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: Text('Delete "${dir.name}" and all its contents? This cannot be undone.'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(parentContext),
            child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Theme.of(parentContext).colorScheme.error),
          onPressed: () async {
            Navigator.pop(parentContext);
            try {
              onCloseUnder(dir.path);
              if (_isRemote(parentContext, dir.path)) {
                final ssh = parentContext.read<SshProvider>();
                final cmd = ssh.remoteIsWindows
                    ? 'cmd /c rmdir /s /q "${dir.path}"'
                    : 'rm -rf "${dir.path}"';
                await ssh.execute(cmd);
              } else {
                await Directory(dir.path).delete(recursive: true);
              }
              onRefresh();
            } catch (e) {
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
          child: const Text('Delete'),
        ),
      ],
    );
  }

  void _showNewItem(BuildContext context, {required bool isFile}) {
    Navigator.pop(context);
    final ctrl = TextEditingController();
    showThemedDialog(
      context: parentContext,
      title: isFile ? 'New file' : 'New folder',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: isFile ? 'filename.dart' : 'folder_name',
            border: const OutlineInputBorder(),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(parentContext),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final name = ctrl.text.trim();
            if (name.isEmpty) return;
            Navigator.pop(parentContext);
            final newPath = '${dir.path}/$name';
            try {
              if (_isRemote(parentContext, dir.path)) {
                final ssh = parentContext.read<SshProvider>();
                if (isFile) {
                  await ssh.writeFile(newPath, '');
                  onRefresh();
                  await onOpenFile(newPath);
                } else {
                  await ssh.createDirectory(newPath);
                  onRefresh();
                }
              } else {
                if (isFile) {
                  await File(newPath).create(recursive: true);
                  onRefresh();
                  await onOpenFile(newPath);
                } else {
                  await Directory(newPath).create(recursive: true);
                  onRefresh();
                }
              }
            } catch (e) {
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
          child: const Text('Create'),
        ),
      ],
    );
  }

  void _showRename(BuildContext context) {
    Navigator.pop(context);
    final ctrl = TextEditingController(text: dir.name);
    showThemedDialog(
      context: parentContext,
      title: 'Rename folder',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(parentContext),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final newName = ctrl.text.trim();
            if (newName.isEmpty) return;
            Navigator.pop(parentContext);
            final sep = dir.path.contains('/') ? '/' : r'\';
            final parent =
                dir.path.substring(0, dir.path.lastIndexOf(sep));
            try {
              if (_isRemote(parentContext, dir.path)) {
                await parentContext
                    .read<SshProvider>()
                    .rename(dir.path, '$parent/$newName');
              } else {
                await Directory(dir.path).rename('$parent/$newName');
              }
              onRefresh();
            } catch (e) {
              if (parentContext.mounted) {
                ScaffoldMessenger.of(parentContext)
                    .showSnackBar(SnackBar(content: Text('Error: $e')));
              }
            }
          },
          child: const Text('Rename'),
        ),
      ],
    );
  }
}

// ── Shared action row widget ──────────────────────────────────────────────────

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _SheetAction({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.onSurface;
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 22, color: c),
      title: Text(label, style: TextStyle(color: c, fontSize: 14)),
      onTap: onTap,
    );
  }
}
