import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/debug_provider.dart';

/// Compact debug action toolbar shown while a session is active.
class DebugToolbar extends StatelessWidget {
  final String projectName;
  const DebugToolbar({super.key, required this.projectName});

  @override
  Widget build(BuildContext context) {
    return Consumer<DebugProvider>(
      builder: (context, dbg, _) {
        if (!dbg.isActive) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        final paused = dbg.isPaused;

        return Container(
          height: 40,
          color: cs.surfaceContainerHighest,
          child: Row(
            children: [
              const SizedBox(width: 8),
              // Session label
              Icon(Icons.bug_report_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 4),
              Text(
                'Debug · ${dbg.status.label}',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              // Continue ▷
              _Btn(
                icon: Icons.play_arrow_rounded,
                tooltip: 'Continue',
                enabled: paused,
                color: Colors.green,
                onTap: () => dbg.continueExec(),
              ),
              // Pause ⏸
              _Btn(
                icon: Icons.pause_rounded,
                tooltip: 'Pause',
                enabled: dbg.isRunning,
                onTap: () => dbg.pause(),
              ),
              // Step over ⤼
              _Btn(
                icon: Icons.redo_rounded,
                tooltip: 'Step Over',
                enabled: paused,
                onTap: () => dbg.stepOver(),
              ),
              // Step in ↓
              _Btn(
                icon: Icons.south_rounded,
                tooltip: 'Step In',
                enabled: paused,
                onTap: () => dbg.stepIn(),
              ),
              // Step out ↑
              _Btn(
                icon: Icons.north_rounded,
                tooltip: 'Step Out',
                enabled: paused,
                onTap: () => dbg.stepOut(),
              ),
              // Restart ↺
              _Btn(
                icon: Icons.refresh_rounded,
                tooltip: 'Restart',
                enabled: paused || dbg.isRunning,
                onTap: () => dbg.restart(),
              ),
              // Stop ■
              _Btn(
                icon: Icons.stop_rounded,
                tooltip: 'Stop',
                color: cs.error,
                enabled: true,
                onTap: () => dbg.stopSession(),
              ),
              const SizedBox(width: 4),
            ],
          ),
        );
      },
    );
  }
}

class _Btn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final Color? color;
  final VoidCallback onTap;

  const _Btn({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effective = color ?? cs.onSurface;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: enabled ? effective : cs.onSurface.withValues(alpha: 0.3),
        onPressed: enabled ? onTap : null,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        splashRadius: 16,
      ),
    );
  }
}

extension on DebugStatus {
  String get label {
    switch (this) {
      case DebugStatus.idle: return 'idle';
      case DebugStatus.starting: return 'starting…';
      case DebugStatus.running: return 'running';
      case DebugStatus.paused: return 'paused';
      case DebugStatus.terminating: return 'stopping…';
    }
  }
}
