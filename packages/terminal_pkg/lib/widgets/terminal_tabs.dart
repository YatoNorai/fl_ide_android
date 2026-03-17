import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/terminal_provider.dart';
import 'pty_terminal_widget.dart';

/// Full terminal panel: tab bar at top + active terminal body.
/// Drop this widget anywhere in the IDE layout.
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
            onNew: () => _newSession(context, provider),
          );
        }

        return Column(
          children: [
            _TabBar(provider: provider, onNew: () => _newSession(context, provider)),
            Expanded(
              child: provider.active != null
                  ? PtyTerminalWidget(session: provider.active!)
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  void _newSession(BuildContext context, TerminalProvider provider) {
    provider.createSession(
      workingDirectory: initialWorkDir,
      environment: extraEnv,
    );
  }
}

class _TabBar extends StatelessWidget {
  final TerminalProvider provider;
  final VoidCallback onNew;

  const _TabBar({required this.provider, required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 35,
      color: AppTheme.darkTabBar,
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: provider.sessions.length,
              itemBuilder: (context, i) {
                final isActive = i == provider.activeIndex;
                final session = provider.sessions[i];
                return _Tab(
                  label: session.label,
                  isActive: isActive,
                  onTap: () => provider.switchTo(i),
                  onClose: () => provider.closeSession(i),
                );
              },
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add, size: 16, color: AppTheme.darkTextMuted),
            onPressed: onNew,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            tooltip: 'New terminal',
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _Tab({
    required this.label,
    required this.isActive,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 35,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.darkPanel : AppTheme.darkTabBar,
          border: Border(
            top: BorderSide(
              color: isActive ? AppTheme.darkAccent : Colors.transparent,
              width: 1,
            ),
            right: const BorderSide(color: AppTheme.darkBorder, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.terminal, size: 12, color: AppTheme.darkTextMuted),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isActive ? AppTheme.darkText : AppTheme.darkTextMuted,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onClose,
              child: const Icon(Icons.close, size: 12, color: AppTheme.darkTextMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyTerminal extends StatelessWidget {
  final VoidCallback onNew;
  const _EmptyTerminal({required this.onNew});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.darkPanel,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.terminal, size: 48, color: AppTheme.darkTextMuted),
            const SizedBox(height: 12),
            const Text('No terminal open',
                style: TextStyle(color: AppTheme.darkTextMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.darkAccent,
                  foregroundColor: Colors.white),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('New Terminal'),
              onPressed: onNew,
            ),
          ],
        ),
      ),
    );
  }
}
