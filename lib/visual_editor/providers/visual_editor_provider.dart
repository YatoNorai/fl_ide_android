import 'package:flutter/material.dart';

import '../models/widget_node.dart';
import '../utils/dart_widget_parser.dart';

enum PreviewMode { rectangle, phone, tablet }

class VisualEditorProvider extends ChangeNotifier {
  // ── Preview mode ──────────────────────────────────────────────────────────
  PreviewMode _previewMode = PreviewMode.phone;
  PreviewMode get previewMode => _previewMode;

  void setPreviewMode(PreviewMode m) {
    _previewMode = m;
    notifyListeners();
  }

  // ── Undo / redo ───────────────────────────────────────────────────────────
  final List<WidgetNode?> _undoStack = [];
  final List<WidgetNode?> _redoStack = [];
  static const int _maxUndoSteps = 30;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  /// Call BEFORE any mutation (addWidget, removeWidget, updateProperty, moveWidget).
  void _pushUndo() {
    _undoStack.add(_root?.deepCopy());
    if (_undoStack.length > _maxUndoSteps) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undo() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_root?.deepCopy());
    _root = _undoStack.removeLast();
    _selected = null;
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_root?.deepCopy());
    _root = _redoStack.removeLast();
    _selected = null;
    notifyListeners();
  }

  // ── Drag state ────────────────────────────────────────────────────────────
  String? _draggingId;
  String? get draggingId => _draggingId;

  void startDrag(String id) {
    _draggingId = id;
    notifyListeners();
  }

  void endDrag() {
    _draggingId = null;
    notifyListeners();
  }

  // ── Active tab index (0=palette, 1=tree, 2=properties) ───────────────────
  int _activeTabIndex = 0;

  int get activeTabIndex => _activeTabIndex;

  void setActiveTab(int index) {
    if (_activeTabIndex == index) return;
    _activeTabIndex = index;
    notifyListeners();
  }

  // ── Widget tree ───────────────────────────────────────────────────────────
  WidgetNode? _root;
  WidgetNode? get root => _root;

  bool get hasRoot => _root != null;

  void setRoot(WidgetNode node) {
    _root = node;
    _selected = null;
    notifyListeners();
  }

  void clearRoot() {
    _root = null;
    _selected = null;
    notifyListeners();
  }

  // ── Selection ─────────────────────────────────────────────────────────────
  String? _selected;
  String? get selectedId => _selected;

  WidgetNode? get selectedNode =>
      _selected != null ? _root?.findById(_selected!) : null;

  void select(String? id) {
    _selected = id;
    notifyListeners();
  }

  void deselect() => select(null);

  // ── Add widget ────────────────────────────────────────────────────────────

  /// Add [child] to the canvas.
  /// If [parentId] is null and there's no root, [child] becomes root.
  /// If [parentId] is null and root exists, tries to add to selected node or root.
  void addWidget(WidgetNode child, {String? parentId}) {
    _pushUndo();
    if (_root == null) {
      _root = child;
      _selected = child.id;
      notifyListeners();
      return;
    }

    final targetId = parentId ?? _selected ?? _root!.id;
    final target = _root!.findById(targetId);
    if (target == null || !target.canHaveChildren) {
      // Try root
      if (_root!.canHaveChildren) {
        if (!_root!.canHaveMultipleChildren && _root!.children.isNotEmpty) return;
        _root!.children.add(child);
      }
    } else {
      if (!target.canHaveMultipleChildren && target.children.isNotEmpty) return;
      target.children.add(child);
    }
    _selected = child.id;
    notifyListeners();
  }

  // ── Remove widget ─────────────────────────────────────────────────────────
  void removeWidget(String nodeId) {
    if (_root == null) return;
    _pushUndo();
    if (_root!.id == nodeId) {
      _root = null;
      _selected = null;
      notifyListeners();
      return;
    }
    final parent = _root!.findParentOf(nodeId);
    if (parent != null) {
      parent.children.removeWhere((c) => c.id == nodeId);
      if (_selected == nodeId) _selected = parent.id;
      notifyListeners();
    }
  }

  // ── Update property ───────────────────────────────────────────────────────
  void updateProperty(String nodeId, String key, dynamic value) {
    final node = _root?.findById(nodeId);
    if (node == null) return;
    _pushUndo();
    if (value == null || (value is String && value.isEmpty)) {
      node.properties.remove(key);
    } else {
      node.properties[key] = value;
    }
    notifyListeners();
  }

  // ── Move widget ───────────────────────────────────────────────────────────
  void moveWidget(String nodeId, String newParentId, {int? index}) {
    if (_root == null) return;
    _pushUndo();
    final node = _root!.findById(nodeId);
    if (node == null || node.id == _root!.id) return;

    final oldParent = _root!.findParentOf(nodeId);
    final newParent = _root!.findById(newParentId);
    if (oldParent == null || newParent == null) return;
    if (!newParent.canHaveChildren) return;
    if (!newParent.canHaveMultipleChildren && newParent.children.isNotEmpty) return;

    oldParent.children.removeWhere((c) => c.id == nodeId);
    if (index != null && index <= newParent.children.length) {
      newParent.children.insert(index, node);
    } else {
      newParent.children.add(node);
    }
    _selected = nodeId;
    notifyListeners();
  }

  // ── Code generation ───────────────────────────────────────────────────────

  /// Generate the full Dart source by replacing the return expression in
  /// the build() method of [originalSource] with the current widget tree.
  /// Returns null if [originalSource] is empty or generation fails.
  String? generateSource(String originalSource) {
    if (_root == null || originalSource.isEmpty) return null;
    final code = _root!.toCode(2);
    if (code.isEmpty) return null;
    final parser = DartWidgetParser();
    final result = parser.replaceReturnInBuild(originalSource, '\n    $code\n  ');
    return result == originalSource ? null : result;
  }

  String generateCode() {
    if (_root == null) return '';
    return _root!.toCode(2);
  }

  String generateFullCode() {
    final body = generateCode();
    if (body.isEmpty) return '';
    return '''import 'package:flutter/material.dart';

class VisualEditorWidget extends StatelessWidget {
  const VisualEditorWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return $body;
  }
}
''';
  }
}
