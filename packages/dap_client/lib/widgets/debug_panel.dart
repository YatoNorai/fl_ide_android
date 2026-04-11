import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dap_types.dart';
import '../providers/debug_provider.dart';

// ── Standalone panels (used as individual tabs in the bottom sheet) ────────────

class DebugVariablesPanel extends StatelessWidget {
  const DebugVariablesPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) => dbg.isActive ? _VariablesTab(dbg: dbg) : const _IdlePane(),
    );
  }
}

class DebugCallStackPanel extends StatelessWidget {
  const DebugCallStackPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) => dbg.isActive ? _CallStackTab(dbg: dbg) : const _IdlePane(),
    );
  }
}

class DebugOutputPanel extends StatelessWidget {
  /// Called when the user taps a file:line link in the output.
  /// The caller (workspace) is responsible for opening the file and
  /// navigating to the given 1-based line.
  final void Function(String filePath, int line)? onNavigate;

  const DebugOutputPanel({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) =>
          _OutputTab(dbg: dbg, onNavigate: onNavigate),
    );
  }
}

/// Breakpoints panel: file breakpoints list + All/Uncaught exception toggles.
class DebugBreakpointsPanel extends StatelessWidget {
  const DebugBreakpointsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) => _BreakpointsTab(dbg: dbg),
    );
  }
}

/// Watch expressions panel.
class DebugWatchPanel extends StatelessWidget {
  const DebugWatchPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) => _WatchTab(dbg: dbg),
    );
  }
}

// ── Idle pane ─────────────────────────────────────────────────────────────────

class _IdlePane extends StatelessWidget {
  const _IdlePane();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bug_report_outlined, size: 36,
              color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text('No active debug session',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Tap  ▶  with the bug icon to start debugging',
              style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Variables tab ─────────────────────────────────────────────────────────────

class _VariablesTab extends StatelessWidget {
  final DebugProvider dbg;
  const _VariablesTab({required this.dbg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!dbg.isPaused) {
      return Center(
        child: Text(
          dbg.isRunning ? 'Running…' : '',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      );
    }

    if (dbg.scopes.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        if (dbg.scopes.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Wrap(
              spacing: 6,
              children: dbg.scopes.map((s) {
                return ActionChip(
                  label: Text(s.name, style: const TextStyle(fontSize: 11)),
                  onPressed: () => dbg.fetchVariables(s.variablesReference),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ),
        if (dbg.variables.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No variables',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          )
        else
          ...dbg.variables.map((v) => _VariableTile(variable: v, dbg: dbg)),
      ],
    );
  }
}

class _VariableTile extends StatelessWidget {
  final DapVariable variable;
  final DebugProvider dbg;
  const _VariableTile({required this.variable, required this.dbg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: variable.hasChildren
          ? () => dbg.fetchVariables(variable.variablesReference)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (variable.hasChildren)
              Padding(
                padding: const EdgeInsets.only(top: 1, right: 4),
                child: Icon(Icons.chevron_right_rounded, size: 14, color: cs.onSurfaceVariant),
              )
            else
              const SizedBox(width: 18),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(fontFamily: 'FiraCode', fontSize: 12, height: 1.4),
                  children: [
                    TextSpan(text: variable.name, style: TextStyle(color: cs.primary)),
                    TextSpan(text: ' = ', style: TextStyle(color: cs.onSurfaceVariant)),
                    TextSpan(text: variable.value, style: TextStyle(color: cs.tertiary)),
                    if (variable.type != null)
                      TextSpan(
                          text: '  // ${variable.type}',
                          style: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Call stack tab ────────────────────────────────────────────────────────────

class _CallStackTab extends StatelessWidget {
  final DebugProvider dbg;
  const _CallStackTab({required this.dbg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!dbg.isPaused) {
      return Center(
        child: Text(
          dbg.isRunning ? 'Running…' : '',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
      );
    }
    if (dbg.callStack.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: dbg.callStack.length,
      itemBuilder: (ctx, i) {
        final frame = dbg.callStack[i];
        final isSelected = frame.id == dbg.currentFrameId;
        return ListTile(
          dense: true,
          selected: isSelected,
          selectedTileColor: cs.primaryContainer.withValues(alpha: 0.3),
          leading: Icon(
            isSelected ? Icons.arrow_right_rounded : Icons.code_rounded,
            size: 16,
            color: isSelected ? cs.primary : cs.onSurfaceVariant,
          ),
          title: Text(
            frame.name,
            style: TextStyle(
              fontSize: 12,
              color: isSelected ? cs.onSurface : cs.onSurfaceVariant,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: frame.sourceName != null
              ? Text('${frame.sourceName}:${frame.line}',
                  style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))
              : null,
          onTap: () => dbg.selectFrame(frame),
        );
      },
    );
  }
}

// ── Output tab (errors in red) ────────────────────────────────────────────────

class _OutputTab extends StatelessWidget {
  final DebugProvider dbg;
  final void Function(String filePath, int line)? onNavigate;

  const _OutputTab({required this.dbg, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (dbg.output.isEmpty) {
      return Center(
        child: Text('No output yet',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(10),
      child: _ColorizedOutput(text: dbg.output, onNavigate: onNavigate),
    );
  }
}

class _ColorizedOutput extends StatelessWidget {
  // Detects /absolute/path/file.dart:line or package:pkg/file.dart:line
  static final _fileLineRe = RegExp(
    r'((?:/[\w./\-]+\.dart)|(?:package:[\w./\-]+\.dart)):(\d+)',
  );
  final String text;
  final void Function(String filePath, int line)? onNavigate;

  const _ColorizedOutput({required this.text, this.onNavigate});

  static final _errorPrefixes = [
    'error:', 'Error:', 'ERROR:',
    '[error]', '[ERROR]',
    'exception:', 'Exception:',
    'fatal:', 'FATAL:',
    '✗', '×',
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = text.split('\n');
    return Text.rich(
      TextSpan(
        style: const TextStyle(
            fontFamily: 'FiraCode', fontSize: 11, height: 1.5),
        children: lines.map((line) => _buildLine(line, cs)).toList(),
      ),
    );
  }

  InlineSpan _buildLine(String line, ColorScheme cs) {
    final isError = _errorPrefixes.any((p) => line.contains(p)) ||
        line.contains('EXCEPTION') ||
        line.contains('Unhandled exception') ||
        (line.trimLeft().startsWith('[adapter]') && line.contains('error'));
    final lineColor = isError ? cs.error : cs.onSurface;

    // Try to find a file:line pattern to make it tappable
    if (onNavigate != null) {
      final match = _fileLineRe.firstMatch(line);
      if (match != null) {
        final filePath = match.group(1)!;
        final lineNum = int.tryParse(match.group(2)!) ?? 1;
        final before = line.substring(0, match.start);
        final linkText = match.group(0)!;
        final after = line.substring(match.end);

        final recognizer = TapGestureRecognizer()
          ..onTap = () => onNavigate!(filePath, lineNum);

        return TextSpan(children: [
          if (before.isNotEmpty)
            TextSpan(text: before, style: TextStyle(color: lineColor)),
          TextSpan(
            text: linkText,
            recognizer: recognizer,
            style: TextStyle(
              color: cs.primary,
              decoration: TextDecoration.underline,
              decorationColor: cs.primary,
            ),
          ),
          if (after.isNotEmpty)
            TextSpan(text: '$after\n', style: TextStyle(color: lineColor)),
          if (after.isEmpty)
            TextSpan(text: '\n', style: TextStyle(color: lineColor)),
        ]);
      }
    }

    return TextSpan(
      text: '$line\n',
      style: TextStyle(color: lineColor),
    );
  }
}

// ── Breakpoints tab ───────────────────────────────────────────────────────────

class _BreakpointsTab extends StatelessWidget {
  final DebugProvider dbg;
  const _BreakpointsTab({required this.dbg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bps = dbg.breakpoints;
    final allFiles = bps.keys.where((k) => bps[k]!.isNotEmpty).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        // Exception breakpoint toggles
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('EXCEPTION BREAKPOINTS',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: cs.onSurfaceVariant)),
        ),
        _ExceptionToggle(
          label: 'All Exceptions',
          value: dbg.breakOnAllExceptions,
          onChanged: dbg.setBreakOnAllExceptions,
        ),
        _ExceptionToggle(
          label: 'Uncaught Exceptions',
          value: dbg.breakOnUncaughtExceptions,
          onChanged: dbg.setBreakOnUncaughtExceptions,
        ),
        const Divider(height: 16),
        // Line breakpoints grouped by file
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('LINE BREAKPOINTS',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: cs.onSurfaceVariant)),
              if (allFiles.isNotEmpty)
                TextButton(
                  onPressed: () {
                    for (final f in allFiles) {
                      for (final line in List<int>.from(bps[f]!)) {
                        dbg.toggleBreakpoint(f, line);
                      }
                    }
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text('Remove all', style: TextStyle(fontSize: 11, color: cs.error)),
                ),
            ],
          ),
        ),
        if (allFiles.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No breakpoints set.\nClick in the gutter to add one.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
          )
        else
          for (final file in allFiles) ...[
            // File header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 2),
              child: Text(
                file.split('/').last,
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            for (final line in bps[file]!)
              ListTile(
                dense: true,
                leading: Icon(Icons.circle, size: 10, color: cs.error),
                title: Text('Line $line',
                    style: const TextStyle(fontSize: 12)),
                trailing: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  onPressed: () => dbg.toggleBreakpoint(file, line),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ),
          ],
      ],
    );
  }
}

class _ExceptionToggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ExceptionToggle({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? value),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 10),
            Text(label,
                style: TextStyle(fontSize: 13, color: cs.onSurface)),
          ],
        ),
      ),
    );
  }
}

// ── Watch tab ─────────────────────────────────────────────────────────────────

class _WatchTab extends StatefulWidget {
  final DebugProvider dbg;
  const _WatchTab({required this.dbg});

  @override
  State<_WatchTab> createState() => _WatchTabState();
}

class _WatchTabState extends State<_WatchTab> {
  final _ctrl = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _addWatch() {
    final expr = _ctrl.text.trim();
    if (expr.isNotEmpty) {
      widget.dbg.addWatch(expr);
      _ctrl.clear();
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final expressions = widget.dbg.watchExpressions;
    final results = widget.dbg.watchResults;

    return Column(
      children: [
        // Add expression bar
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _editing
              ? Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        style: const TextStyle(fontFamily: 'FiraCode', fontSize: 12),
                        decoration: InputDecoration(
                          hintText: 'Expression…',
                          hintStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        onSubmitted: (_) => _addWatch(),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.check_rounded, size: 18),
                      onPressed: _addWatch,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _editing = false);
                      },
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                )
              : Row(
                  children: [
                    Text('WATCH',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: cs.onSurfaceVariant)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: () => setState(() => _editing = true),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Add watch expression',
                    ),
                    if (widget.dbg.isPaused)
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        onPressed: widget.dbg.evaluateAllWatches,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Refresh all',
                      ),
                  ],
                ),
        ),
        const Divider(height: 1),
        Expanded(
          child: expressions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.visibility_outlined, size: 32,
                          color: cs.onSurfaceVariant.withValues(alpha: 0.4)),
                      const SizedBox(height: 8),
                      Text('No watch expressions',
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                      const SizedBox(height: 4),
                      Text('Tap + to add an expression to watch',
                          style: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                              fontSize: 11)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: expressions.length,
                  itemBuilder: (ctx, i) {
                    final expr = expressions[i];
                    final result = results[expr];
                    return ListTile(
                      dense: true,
                      leading: Icon(Icons.circle_outlined, size: 10, color: cs.primary),
                      title: Text(expr,
                          style: const TextStyle(fontFamily: 'FiraCode', fontSize: 12)),
                      subtitle: result != null
                          ? Text(result,
                              style: TextStyle(
                                  fontFamily: 'FiraCode',
                                  fontSize: 11,
                                  color: cs.tertiary))
                          : Text(
                              widget.dbg.isPaused ? 'evaluating…' : 'not paused',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 14),
                        onPressed: () => widget.dbg.removeWatch(expr),
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// ── Legacy full panel (kept for backwards compat) ─────────────────────────────

class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) =>
          dbg.isActive ? _DebugActiveView(dbg: dbg) : const _IdlePane(),
    );
  }
}

class _DebugActiveView extends StatelessWidget {
  final DebugProvider dbg;
  const _DebugActiveView({required this.dbg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 11),
            labelColor: cs.primary,
            unselectedLabelColor: cs.onSurfaceVariant,
            indicatorSize: TabBarIndicatorSize.label,
            dividerHeight: 0,
            tabs: const [
              Tab(text: 'VARIABLES'),
              Tab(text: 'CALL STACK'),
              Tab(text: 'OUTPUT'),
            ],
          ),
          const Divider(height: 1, thickness: 1),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _VariablesTab(dbg: dbg),
                _CallStackTab(dbg: dbg),
                _OutputTab(dbg: dbg),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
