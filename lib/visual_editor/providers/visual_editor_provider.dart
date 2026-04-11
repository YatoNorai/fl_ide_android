import 'package:flutter/material.dart';

import '../models/widget_node.dart';

enum PreviewMode { rectangle, phone, tablet }

class VisualEditorProvider extends ChangeNotifier {
  // ── Preview mode ──────────────────────────────────────────────────────────
  PreviewMode _previewMode = PreviewMode.phone;
  PreviewMode get previewMode => _previewMode;

  void setPreviewMode(PreviewMode m) {
    _previewMode = m;
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
