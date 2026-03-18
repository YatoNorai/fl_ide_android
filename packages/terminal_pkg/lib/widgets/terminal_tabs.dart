import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/terminal_provider.dart';
import 'pty_terminal_widget.dart';

/// Terminal body: shows the active session's xterm widget.
/// Tab management (chips/header) is handled by the parent screen.
class TerminalTabs extends StatelessWidget {
  final String? initialWorkDir;
  final Map<String, String>? extraEnv;

  const TerminalTabs({
    super.key,
    this.initialWorkDir,
    this.extraEnv,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<TerminalProvider>(
      builder: (context, provider, _) {
        if (provider.sessions.isEmpty) {
          return _EmptyTerminal(
            onNew: () => provider.createSession(
              workingDirectory: initialWorkDir,
              environment: extraEnv,
            ),
          );
        }

        return provider.active != null
            ? PtyTerminalWidget(session: provider.active!)
            : const SizedBox.shrink();
      },
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyTerminal extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyTerminal({required this.onNew});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceTint.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.terminal, size: 40,
                color: colors.onSurface.withValues(alpha: 0.35)),
          ),
          const SizedBox(height: 16),
          Text(
            'No terminal open',
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.5),
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
