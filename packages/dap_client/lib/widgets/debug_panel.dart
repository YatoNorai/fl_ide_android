import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dap_types.dart';
import '../providers/debug_provider.dart';

/// Full debug panel: call stack + variables + debug output in a tab layout.
/// Used when all 3 tabs are shown as sub-tabs (legacy usage).
class DebugPanel extends StatelessWidget {
  const DebugPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) {
        if (!dbg.isActive) {
          return _IdlePane();
        }
        return _DebugActiveView(dbg: dbg);
      },
    );
  }
}

// ── Individual panels (used as standalone tabs) ────────────────────────────

/// Variables tab content — usable as a standalone main tab.
class DebugVariablesPanel extends StatelessWidget {
  const DebugVariablesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) {
        if (!dbg.isActive) return const _IdlePane();
        return _VariablesTab(dbg: dbg);
      },
    );
  }
}

/// Call stack tab content — usable as a standalone main tab.
class DebugCallStackPanel extends StatelessWidget {
  const DebugCallStackPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) {
        if (!dbg.isActive) return const _IdlePane();
        return _CallStackTab(dbg: dbg);
      },
    );
  }
}

/// Output tab content — usable as a standalone main tab.
class DebugOutputPanel extends StatelessWidget {
  const DebugOutputPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) {
        if (!dbg.isActive) return const _IdlePane();
        return _OutputTab(dbg: dbg);
      },
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
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontSize: 13)),
          const SizedBox(height: 4),
          Text('Tap  ▶  with the bug icon to start debugging',
              style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 11)),
        ],
      ),
    );
  }
}

// ── Active view (DefaultTabController with 3 sub-tabs) ────────────────────────

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
            labelStyle: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600),
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
        // Scope selector chips
        if (dbg.scopes.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Wrap(
              spacing: 6,
              children: dbg.scopes.map((s) {
                return ActionChip(
                  label: Text(s.name,
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () => dbg.fetchVariables(s.variablesReference),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                );
              }).toList(),
            ),
          ),
        // Variables list
        if (dbg.variables.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No variables',
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontSize: 12)),
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
    final nameColor = cs.primary;
    final valueColor = cs.tertiary;

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
                child: Icon(Icons.chevron_right_rounded,
                    size: 14, color: cs.onSurfaceVariant),
              )
            else
              const SizedBox(width: 18),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontFamily: 'FiraCode', fontSize: 12, height: 1.4),
                  children: [
                    TextSpan(
                        text: variable.name,
                        style: TextStyle(color: nameColor)),
                    TextSpan(
                        text: ' = ',
                        style: TextStyle(color: cs.onSurfaceVariant)),
                    TextSpan(
                        text: variable.value,
                        style: TextStyle(color: valueColor)),
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
            isSelected
                ? Icons.arrow_right_rounded
                : Icons.code_rounded,
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
              ? Text(
                  '${frame.sourceName}:${frame.line}',
                  style: TextStyle(
                      fontSize: 10, color: cs.onSurfaceVariant),
                )
              : null,
          onTap: () => dbg.selectFrame(frame),
        );
      },
    );
  }
}

// ── Output tab ────────────────────────────────────────────────────────────────

class _OutputTab extends StatelessWidget {
  final DebugProvider dbg;
  const _OutputTab({required this.dbg});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (dbg.output.isEmpty) {
      return Center(
        child: Text('No output yet',
            style: TextStyle(
                color: cs.onSurfaceVariant, fontSize: 12)),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        dbg.output,
        style: const TextStyle(
          fontFamily: 'FiraCode',
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }
}

