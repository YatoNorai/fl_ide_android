import '../models/widget_node.dart';

/// Parses a Dart source file containing a [StatelessWidget] or
/// [StatefulWidget] and extracts its widget tree into [WidgetNode]s.
class DartWidgetParser {
  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns true if [source] declares a Flutter widget class.
  bool isFlutterWidget(String source) {
    return _buildBodyOf(source) != null;
  }

  /// Parse [source] and return the widget tree from the build() method.
  /// Returns null if not a Flutter widget or parse fails.
  WidgetNode? parseSource(String source) {
    final body = _buildBodyOf(source);
    if (body == null) return null;
    final expr = _returnExpr(body);
    if (expr == null || expr.isEmpty) return null;
    return _parseExpr(expr.trim());
  }

  /// Replace the return expression in the build() method with [newWidgetCode].
  /// Returns the modified source, or the original source if replacement fails.
  String replaceReturnInBuild(String source, String newWidgetCode) {
    // Find the same build() method that parseSource() would use
    final buildMatch = _bestBuildMatch(source);
    if (buildMatch == null) return source;

    final braceOpen = source.indexOf('{', buildMatch.end - 1);
    if (braceOpen == -1) return source;

    final braceClose = _findMatching(source, braceOpen, '{', '}');
    if (braceClose == -1) return source;

    final body = source.substring(braceOpen + 1, braceClose);

    // Find the last `return ` in the body
    final returnIdx = body.lastIndexOf('return ');
    if (returnIdx == -1) return source;

    final exprStart = braceOpen + 1 + returnIdx + 7; // after 'return '
    // Find the semicolon that ends this return (balanced)
    final semiOffset = _findReturnSemi(body, returnIdx + 7);
    if (semiOffset == -1) return source;
    final exprEnd = braceOpen + 1 + semiOffset;

    return source.substring(0, exprStart) +
        newWidgetCode +
        source.substring(exprEnd);
  }

  // ── Internal helpers ───────────────────────────────────────────────────────

  static final _buildMethodRegex = RegExp(
    r'Widget\s+build\s*\(\s*BuildContext\s+\w+\s*\)',
  );

  static final _appWrapperRegex = RegExp(
    r'^(?:const\s+)?(?:Material|Cupertino)App\s*\(',
  );

  static final _widgetClassRegex = RegExp(
    r'extends\s+(StatelessWidget|StatefulWidget|State\s*<)',
  );

  static final _uppercaseStartRegex = RegExp(r'^[A-Z]');

  static final _identifierRegex = RegExp(r'^[A-Za-z_][A-Za-z0-9_.]*$');

  static final _widgetCallRegex = RegExp(r'^[A-Z][A-Za-z0-9_]*\s*\(');

  /// Finds the best [RegExpMatch] for a `build()` method in [source].
  /// Prefers build() bodies that do NOT return a MaterialApp/CupertinoApp
  /// (i.e., the actual screen widget, not the app wrapper).
  RegExpMatch? _bestBuildMatch(String source) {
    final allMatches = _buildMethodRegex.allMatches(source).toList();
    if (allMatches.isEmpty) return null;

    RegExpMatch? fallback;
    for (final m in allMatches) {
      final braceOpen = source.indexOf('{', m.end - 1);
      if (braceOpen == -1) continue;
      final braceClose = _findMatching(source, braceOpen, '{', '}');
      if (braceClose == -1) continue;
      final body = source.substring(braceOpen + 1, braceClose);
      final expr = _returnExpr(body)?.trim() ?? '';
      if (!_appWrapperRegex.hasMatch(expr)) return m; // prefer non-app-wrapper
      fallback ??= m;
    }
    return fallback;
  }

  /// Returns the body (between braces) of the build() method, or null.
  /// Skips MaterialApp/CupertinoApp wrappers and prefers the actual screen widget.
  String? _buildBodyOf(String source) {
    // Must be a Widget class
    if (!_widgetClassRegex.hasMatch(source)) return null;

    final m = _bestBuildMatch(source);
    if (m == null) return null;

    final braceOpen = source.indexOf('{', m.end - 1);
    if (braceOpen == -1) return null;

    final braceClose = _findMatching(source, braceOpen, '{', '}');
    if (braceClose == -1) return null;

    return source.substring(braceOpen + 1, braceClose);
  }

  /// Extract the return expression from a method body string.
  String? _returnExpr(String body) {
    // Find last 'return '
    final idx = body.lastIndexOf('return ');
    if (idx == -1) return null;

    final exprStart = idx + 7;
    final semiOffset = _findReturnSemi(body, exprStart);
    if (semiOffset == -1) return null;

    return body.substring(exprStart, semiOffset).trim();
  }

  /// Find the semicolon that terminates a return statement.
  /// [start] is the index right after 'return '.
  int _findReturnSemi(String s, int start) {
    int depth = 0; // tracks (), [], {}
    bool inStr = false;
    String strChar = '';

    for (int i = start; i < s.length; i++) {
      final c = s[i];

      if (inStr) {
        if (c == '\\') { i++; continue; }
        if (c == strChar) inStr = false;
        continue;
      }

      if (c == '"' || c == "'") {
        // Check for triple-quote
        if (i + 2 < s.length && s[i + 1] == c && s[i + 2] == c) {
          // Skip triple-quoted string
          final end = s.indexOf('$c$c$c', i + 3);
          if (end != -1) { i = end + 2; continue; }
        }
        inStr = true;
        strChar = c;
        continue;
      }

      if (c == '(' || c == '[' || c == '{') { depth++; continue; }
      if (c == ')' || c == ']' || c == '}') {
        if (depth > 0) { depth--; continue; }
        // Unmatched close brace — stop here (return expr without trailing semi)
        return i;
      }
      if (c == ';' && depth == 0) return i;
    }
    return -1;
  }

  // ── Expression parser ──────────────────────────────────────────────────────

  WidgetNode? _parseExpr(String expr) {
    expr = expr.trim();

    // Strip leading 'const' or 'new'
    if (expr.startsWith('const ')) expr = expr.substring(6).trim();
    if (expr.startsWith('new ')) expr = expr.substring(4).trim();

    // Must start with an uppercase letter (widget class name)
    if (expr.isEmpty || !_uppercaseStartRegex.hasMatch(expr)) return null;

    final parenIdx = expr.indexOf('(');
    if (parenIdx == -1) {
      // Bare widget name like `Text` — no args
      return WidgetNode(type: expr);
    }

    final widgetName = expr.substring(0, parenIdx).trim();
    // Reject names that contain spaces or non-identifier chars (unlikely but safe)
    if (!_identifierRegex.hasMatch(widgetName)) return null;

    final closeIdx = _findMatching(expr, parenIdx, '(', ')');
    if (closeIdx == -1) return null;

    final argsContent = expr.substring(parenIdx + 1, closeIdx);
    return _buildNode(widgetName, argsContent);
  }

  // Named parameters whose values are widgets (parsed as slotted children).
  static const _widgetSlots = {
    'appBar', 'body', 'floatingActionButton', 'drawer', 'endDrawer',
    'bottomNavigationBar', 'bottomSheet', 'leading', 'trailing',
    'header', 'footer', 'placeholder', 'prefixIcon', 'suffixIcon',
  };

  // Named params that take a list of widgets.
  static const _widgetListSlots = {'actions', 'persistentFooterButtons'};

  /// Returns true if [value] looks like a Flutter widget constructor call.
  bool _looksLikeWidget(String value) {
    final stripped = value.startsWith('const ') ? value.substring(6).trim() : value;
    return _widgetCallRegex.hasMatch(stripped);
  }

  WidgetNode? _buildNode(String type, String argsContent) {
    // Use simple type (drop package qualifier, e.g. 'flutter.Column' → 'Column')
    final simpleName = _classNameOf(type);

    final props = <String, dynamic>{};
    final children = <WidgetNode>[];

    final args = _splitTopLevelArgs(argsContent);

    for (final arg in args) {
      final colonIdx = arg.indexOf(':');
      if (colonIdx == -1) {
        // Positional argument — e.g., Text('Hello') first arg
        if (simpleName == 'Text' && !props.containsKey('text')) {
          props['text'] = _extractStringValue(arg.trim()) ?? arg.trim();
        } else if (simpleName == 'Icon' && !props.containsKey('icon')) {
          props['icon'] = arg.trim();
        }
        continue;
      }

      final key = arg.substring(0, colonIdx).trim();
      final value = arg.substring(colonIdx + 1).trim();

      // ── child / children (standard Flutter parameters) ───────────────
      if (key == 'child') {
        final child = _parseExpr(value);
        if (child != null) children.add(child);
        continue;
      }

      if (key == 'children') {
        final listContent = _extractListContent(value);
        if (listContent != null) {
          for (final item in _splitTopLevelArgs(listContent)) {
            final child = _parseExpr(item.trim());
            if (child != null) children.add(child);
          }
        }
        continue;
      }

      // ── Named widget slots (appBar, body, leading, etc.) ─────────────
      if (_widgetSlots.contains(key) && _looksLikeWidget(value)) {
        final child = _parseExpr(value);
        if (child != null) {
          child.properties['_slot'] = key;
          children.add(child);
        }
        continue;
      }

      if (_widgetListSlots.contains(key)) {
        final listContent = _extractListContent(value);
        if (listContent != null) {
          for (final item in _splitTopLevelArgs(listContent)) {
            final child = _parseExpr(item.trim());
            if (child != null) {
              child.properties['_slot'] = key;
              children.add(child);
            }
          }
        }
        continue;
      }

      // ── title: can be a Text widget or a plain string ─────────────────
      if (key == 'title') {
        if (_looksLikeWidget(value)) {
          // e.g., title: Text('Hello') — extract string content
          final inner = _extractFirstStringArg(value);
          if (inner != null) {
            props['title'] = inner;
          } else {
            // Parse as slotted child if we can't extract string
            final child = _parseExpr(value);
            if (child != null) {
              child.properties['_slot'] = 'title';
              children.add(child);
            }
          }
        } else {
          props['title'] = _extractStringValue(value) ?? value;
        }
        continue;
      }

      // ── label: can be a Text widget or plain string ───────────────────
      if (key == 'label') {
        if (_looksLikeWidget(value)) {
          final inner = _extractFirstStringArg(value);
          props['label'] = inner ?? value;
        } else {
          props['label'] = _extractStringValue(value) ?? value;
        }
        continue;
      }

      switch (key) {
        // ── Known property mappings ──────────────────────────────────────
        case 'text':
          props['text'] = _extractStringValue(value) ?? value;
          break;

        case 'data':
          if (simpleName == 'Text') {
            props['text'] = _extractStringValue(value) ?? value;
          }
          break;

        case 'icon':
          props['icon'] = value;
          break;

        case 'size':
          props['size'] = _numStr(value);
          break;

        case 'width':
          props['width'] = _numStr(value);
          break;

        case 'height':
          props['height'] = _numStr(value);
          break;

        case 'color':
          props['color'] = value;
          break;

        case 'backgroundColor':
          props['backgroundColor'] = value;
          break;

        case 'elevation':
          props['elevation'] = _numStr(value);
          break;

        case 'radius':
          props['radius'] = _numStr(value);
          break;

        case 'borderRadius':
          // Could be BorderRadius.circular(8) — extract number
          final num = _extractBorderRadiusNum(value);
          if (num != null) props['borderRadius'] = num;
          break;

        case 'padding':
          props['padding'] = _extractEdgeInsetsNum(value);
          break;

        case 'margin':
          props['margin'] = _extractEdgeInsetsNum(value);
          break;

        case 'mainAxisAlignment':
          props['mainAxisAlignment'] = value;
          break;

        case 'crossAxisAlignment':
          props['crossAxisAlignment'] = value;
          break;

        case 'alignment':
          props['alignment'] = value;
          break;

        case 'flex':
          props['flex'] = _numStr(value);
          break;

        case 'opacity':
          props['opacity'] = _numStr(value);
          break;

        case 'fontSize':
          props['fontSize'] = _numStr(value);
          break;

        case 'fontWeight':
          props['fontWeight'] = value;
          break;

        case 'message':
          props['message'] = _extractStringValue(value) ?? value;
          break;

        case 'value':
          props['value'] = _numStr(value) ?? value;
          break;

        case 'hintText':
          props['hintText'] = _extractStringValue(value) ?? value;
          break;

        case 'labelText':
          props['labelText'] = _extractStringValue(value) ?? value;
          break;

        case 'fit':
          props['fit'] = value;
          break;

        case 'style':
          // TextStyle(fontSize: 24, fontWeight: ..., color: ...) — extract what we can
          if (value.contains('TextStyle')) {
            final fs = RegExp(r'fontSize:\s*([\d.]+)').firstMatch(value);
            if (fs != null) props['fontSize'] = fs.group(1);
            final fw = RegExp(r'fontWeight:\s*(FontWeight\.\w+)').firstMatch(value);
            if (fw != null) props['fontWeight'] = fw.group(1);
            final clr = RegExp(r'color:\s*(Colors\.\w+(?:\.\w+)?)').firstMatch(value);
            if (clr != null) props['color'] = clr.group(1);
          }
          break;

        case 'crossAxisCount':
          props['crossAxisCount'] = _numStr(value) ?? value;
          break;

        case 'crossAxisSpacing':
          props['crossAxisSpacing'] = _numStr(value);
          break;

        case 'mainAxisSpacing':
          props['mainAxisSpacing'] = _numStr(value);
          break;

        case 'childAspectRatio':
          props['childAspectRatio'] = _numStr(value);
          break;

        case 'initiallyExpanded':
          props['initiallyExpanded'] = value;
          break;

        case 'maxLines':
          props['maxLines'] = _numStr(value) ?? value;
          break;

        case 'textAlign':
          props['textAlign'] = value;
          break;

        case 'overflow':
          props['overflow'] = value;
          break;

        case 'subtitle': {
          if (_looksLikeWidget(value)) {
            final inner = _extractFirstStringArg(value);
            props['subtitle'] = inner ?? value;
          } else {
            props['subtitle'] = _extractStringValue(value) ?? value;
          }
          break;
        }

        case 'tooltip':
          props['tooltip'] = _extractStringValue(value) ?? value;
          break;

        case 'semanticLabel':
        case 'restorationId':
        case 'key':
          // Skip framework-internal params
          break;

        default:
          // Store as-is for unknown properties
          props[key] = value;
      }
    }

    return WidgetNode(type: simpleName, properties: props, children: children);
  }

  /// For named constructors ('ListView.builder' → 'ListView'; 'SizedBox.expand' → 'SizedBox').
  /// Leaves simple names ('Text', 'Row') unchanged.
  static String _classNameOf(String type) {
    if (!type.contains('.')) return type;
    final first = type.split('.').first;
    // First segment starts with uppercase → it's the class name
    if (first.isNotEmpty && first[0] != first[0].toLowerCase()) return first;
    // Otherwise take last segment (package qualifiers, etc.)
    return type.split('.').last;
  }

  // ── Bracket helpers ────────────────────────────────────────────────────────

  /// Find the matching closing bracket for the opening bracket at [openIdx].
  int _findMatching(String s, int openIdx, String open, String close) {
    int depth = 0;
    bool inStr = false;
    String strChar = '';

    for (int i = openIdx; i < s.length; i++) {
      final c = s[i];

      if (inStr) {
        if (c == '\\') { i++; continue; }
        if (c == strChar) inStr = false;
        continue;
      }

      if (c == '"' || c == "'") {
        if (i + 2 < s.length && s[i + 1] == c && s[i + 2] == c) {
          final end = s.indexOf('$c$c$c', i + 3);
          if (end != -1) { i = end + 2; continue; }
        }
        inStr = true;
        strChar = c;
        continue;
      }

      if (c == open) { depth++; continue; }
      if (c == close) {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// Split [s] at top-level commas (not inside brackets or strings).
  List<String> _splitTopLevelArgs(String s) {
    final parts = <String>[];
    int depth = 0;
    bool inStr = false;
    String strChar = '';
    int start = 0;

    for (int i = 0; i < s.length; i++) {
      final c = s[i];

      if (inStr) {
        if (c == '\\') { i++; continue; }
        if (c == strChar) inStr = false;
        continue;
      }

      if (c == '"' || c == "'") {
        if (i + 2 < s.length && s[i + 1] == c && s[i + 2] == c) {
          final end = s.indexOf('$c$c$c', i + 3);
          if (end != -1) { i = end + 2; continue; }
        }
        inStr = true;
        strChar = c;
        continue;
      }

      if (c == '(' || c == '[' || c == '{') { depth++; continue; }
      if (c == ')' || c == ']' || c == '}') { depth--; continue; }

      if (c == ',' && depth == 0) {
        final part = s.substring(start, i).trim();
        if (part.isNotEmpty) parts.add(part);
        start = i + 1;
      }
    }

    final last = s.substring(start).trim();
    if (last.isNotEmpty) parts.add(last);
    return parts;
  }

  /// Extract content between `[` and `]`.
  String? _extractListContent(String s) {
    s = s.trim();
    // Strip leading 'const'
    if (s.startsWith('const ')) s = s.substring(6).trim();
    // Strip generic type annotation: <Widget>[, <T>[, <Map<String,Widget>>[, etc.
    if (s.startsWith('<')) {
      int depth = 0;
      int i = 0;
      while (i < s.length) {
        if (s[i] == '<') depth++;
        else if (s[i] == '>') {
          depth--;
          if (depth == 0) { i++; break; }
        }
        i++;
      }
      s = s.substring(i).trim();
      // Strip another 'const' after type annotation: const <Widget>const [
      if (s.startsWith('const ')) s = s.substring(6).trim();
    }
    if (!s.startsWith('[')) return null;
    final close = _findMatching(s, 0, '[', ']');
    if (close == -1) return null;
    return s.substring(1, close);
  }

  // ── Value helpers ──────────────────────────────────────────────────────────

  String? _extractStringValue(String s) {
    s = s.trim();
    if ((s.startsWith("'") && s.endsWith("'")) ||
        (s.startsWith('"') && s.endsWith('"'))) {
      return s.substring(1, s.length - 1);
    }
    return null;
  }

  String? _between(String s, String open, String close) {
    final start = s.indexOf(open);
    if (start == -1) return null;
    final end = s.indexOf(close, start + 1);
    if (end == -1) return null;
    return s.substring(start + 1, end);
  }

  String? _extractFirstStringArg(String s) {
    final paren = s.indexOf('(');
    if (paren == -1) return null;
    final close = _findMatching(s, paren, '(', ')');
    if (close == -1) return null;
    final args = _splitTopLevelArgs(s.substring(paren + 1, close));
    if (args.isEmpty) return null;
    return _extractStringValue(args.first.trim());
  }

  String? _numStr(String s) {
    s = s.trim();
    return double.tryParse(s) != null ? s : int.tryParse(s) != null ? s : null;
  }

  String? _extractBorderRadiusNum(String s) {
    // BorderRadius.circular(8.0) → '8.0'
    final m = RegExp(r'circular\(([^)]+)\)').firstMatch(s);
    if (m != null) return m.group(1)!.trim();
    return null;
  }

  String? _extractEdgeInsetsNum(String s) {
    // EdgeInsets.all(8.0) → '8.0'
    // EdgeInsets.symmetric(...) → '8.0' (just horizontal value for simplicity)
    final allMatch = RegExp(r'EdgeInsets\.all\(([^)]+)\)').firstMatch(s);
    if (allMatch != null) return allMatch.group(1)!.trim();
    final symMatch =
        RegExp(r'EdgeInsets\.symmetric\([^)]*(?:horizontal|vertical):\s*([\d.]+)')
            .firstMatch(s);
    if (symMatch != null) return symMatch.group(1)!.trim();
    return _numStr(s);
  }
}
