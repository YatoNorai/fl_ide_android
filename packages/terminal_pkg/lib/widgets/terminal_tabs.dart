import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/terminal_session.dart';
import '../providers/terminal_provider.dart';
import 'pty_terminal_widget.dart';

/// Terminal body: shows session chips above the active session's xterm widget.
/// Each chip is [LongPressDraggable<TerminalSession>] — drag it onto the main
/// EditorTabBar to pin it to the top bar.
///
/// When [autoStart] is true (default when [initialWorkDir] is set), a session
/// is automatically created the first time the widget is mounted with no
/// existing sheet sessions, so the terminal is ready immediately.
class TerminalTabs extends StatefulWidget {
  final String? initialWorkDir;
  final Map<String, String>? extraEnv;

  /// When set, new sessions use this SSH setup instead of a local PTY.
  final Future<void> Function(TerminalSession session)? sshSetup;

  /// Auto-create a session on first mount when the sheet has no sessions.
  /// Defaults to true when [initialWorkDir] is provided.
  final bool? autoStart;

  const TerminalTabs({
    super.key,
    this.initialWorkDir,
    this.extraEnv,
    this.sshSetup,
    this.autoStart,
  });

  @override
  State<TerminalTabs> createState() => _TerminalTabsState();
}

class _TerminalTabsState extends State<TerminalTabs> {
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeAutoStart();
  }

  void _maybeAutoStart() {
    final autoStart = widget.autoStart ?? (widget.initialWorkDir != null);
    if (!autoStart || _started) return;
    final provider = context.read<TerminalProvider>();
    if (provider.sheetSessions.isNotEmpty) {
      _started = true;
      return;
    }
    _started = true;
    // Defer to avoid calling provider during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final p = context.read<TerminalProvider>();
      if (p.sheetSessions.isEmpty) {
        p.createSession(
          workingDirectory: widget.initialWorkDir,
          environment: widget.extraEnv,
          sshSetup: widget.sshSetup,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<TerminalProvider>(
      builder: (context, provider, _) {
        final sheetSessions = provider.sheetSessions;

        if (sheetSessions.isEmpty) {
          return _EmptyTerminal(
            onNew: () => provider.createSession(
              workingDirectory: widget.initialWorkDir,
              environment: widget.extraEnv,
              sshSetup: widget.sshSetup,
            ),
          );
        }

        // Active sheet session
        final activeSession =
            provider.active != null && sheetSessions.contains(provider.active)
                ? provider.active!
                : sheetSessions.last;

        return Column(
          children: [
            _SessionChipBar(
              sessions: sheetSessions,
              activeSession: activeSession,
              provider: provider,
              initialWorkDir: widget.initialWorkDir,
              extraEnv: widget.extraEnv,
              sshSetup: widget.sshSetup,
            ),
            Expanded(child: PtyTerminalWidget(session: activeSession)),
          ],
        );
      },
    );
  }
}

// ── Session chip bar ──────────────────────────────────────────────────────────

class _SessionChipBar extends StatelessWidget {
  final List<TerminalSession> sessions;
  final TerminalSession activeSession;
  final TerminalProvider provider;
  final String? initialWorkDir;
  final Map<String, String>? extraEnv;
  final Future<void> Function(TerminalSession session)? sshSetup;

  const _SessionChipBar({
    required this.sessions,
    required this.activeSession,
    required this.provider,
    this.initialWorkDir,
    this.extraEnv,
    this.sshSetup,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      color: cs.surface,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              itemCount: sessions.length,
              itemBuilder: (ctx, i) {
                final session = sessions[i];
                return _SessionChip(
                  session: session,
                  isActive: session.id == activeSession.id,
                  onTap: () {
                    final idx = provider.sessions.indexOf(session);
                    if (idx != -1) provider.switchTo(idx);
                  },
                  onClose: () {
                    final idx = provider.sessions.indexOf(session);
                    if (idx != -1) provider.closeSession(idx);
                  },
                );
              },
            ),
          ),
          // New terminal button
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              icon: const Icon(Icons.add, size: 16),
              padding: EdgeInsets.zero,
              tooltip: 'New Terminal',
              onPressed: () => provider.createSession(
                workingDirectory: initialWorkDir,
                environment: extraEnv,
                sshSetup: sshSetup,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Single draggable session chip ─────────────────────────────────────────────

class _SessionChip extends StatelessWidget {
  final TerminalSession session;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _SessionChip({
    required this.session,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = session.label ?? 'bash';

    return LongPressDraggable<TerminalSession>(
      data: session,
      hapticFeedbackOnStart: true,
      feedback: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(8),
        color: cs.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.terminal, size: 12, color: cs.onPrimaryContainer),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: _chip(cs, label)),
      child: GestureDetector(onTap: onTap, child: _chip(cs, label)),
    );
  }

  Widget _chip(ColorScheme cs, String label) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: isActive
            ? cs.primaryContainer.withValues(alpha: 0.55)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6),
        border: isActive
            ? Border(bottom: BorderSide(color: cs.primary, width: 2))
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.terminal,
              size: 10,
              color: isActive ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? cs.primary : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Icon(
              Icons.close_rounded,
              size: 10,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyTerminal extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyTerminal({required this.onNew});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: cs.surfaceTint.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.terminal,
                size: 40, color: cs.onSurface.withValues(alpha: 0.35)),
          ),
          const SizedBox(height: 16),
          Text(
            'No terminal open',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.5),
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onNew,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('New Terminal'),
          ),
        ],
      ),
    );
  }
}
