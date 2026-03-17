import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/app_installer_provider.dart';

class LogsPanel extends StatefulWidget {
  final String? packageName;

  const LogsPanel({super.key, this.packageName});

  @override
  State<LogsPanel> createState() => _LogsPanelState();
}

class _LogsPanelState extends State<LogsPanel> {
  TerminalSession? _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startLogcat());
  }

  @override
  void dispose() {
    _session?.kill();
    super.dispose();
  }

  Future<void> _startLogcat() async {
    final installer = context.read<AppInstallerProvider>();
    final session = await installer.startLogcat(packageName: widget.packageName);
    setState(() => _session = session);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LogsToolbar(packageName: widget.packageName),
        Expanded(
          child: _session == null
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.darkAccent))
              : PtyTerminalWidget(session: _session!),
        ),
      ],
    );
  }
}

class _LogsToolbar extends StatelessWidget {
  final String? packageName;

  const _LogsToolbar({this.packageName});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppInstallerProvider>(
      builder: (context, installer, _) => Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: const BoxDecoration(
          color: AppTheme.darkTabBar,
          border: Border(bottom: BorderSide(color: AppTheme.darkBorder)),
        ),
        child: Row(
          children: [
            const Icon(Icons.phone_android, size: 14, color: AppTheme.darkTextMuted),
            const SizedBox(width: 8),
            Text(
              packageName != null ? 'Logcat: $packageName' : 'Logcat',
              style: const TextStyle(color: AppTheme.darkTextMuted, fontSize: 12),
            ),
            const Spacer(),
            // Hot reload button
            if (installer.hotReloadAvailable) ...[
              _HotReloadButton(onReload: installer.hotReload),
              const SizedBox(width: 8),
              _HotRestartButton(onRestart: installer.hotRestart),
              const SizedBox(width: 8),
            ],
            IconButton(
              icon: const Icon(Icons.stop, size: 14, color: Colors.redAccent),
              onPressed: installer.stopLogcat,
              tooltip: 'Stop logcat',
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
  }
}

class _HotReloadButton extends StatelessWidget {
  final Future<bool> Function() onReload;

  const _HotReloadButton({required this.onReload});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hot Reload (⚡)',
      child: InkWell(
        onTap: () async {
          final ok = await onReload();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? '⚡ Hot Reload done' : 'Hot Reload failed'),
                backgroundColor: AppTheme.darkSidebar,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFFC107).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: const Color(0xFFFFC107).withValues(alpha: 0.4)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bolt, size: 13, color: Color(0xFFFFC107)),
              SizedBox(width: 4),
              Text('Hot Reload',
                  style: TextStyle(color: Color(0xFFFFC107), fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotRestartButton extends StatelessWidget {
  final Future<bool> Function() onRestart;

  const _HotRestartButton({required this.onRestart});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Hot Restart',
      child: InkWell(
        onTap: () async {
          final ok = await onRestart();
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ok ? '🔄 Hot Restart done' : 'Hot Restart failed'),
                backgroundColor: AppTheme.darkSidebar,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.darkBorder.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.restart_alt, size: 13, color: AppTheme.darkTextMuted),
              SizedBox(width: 4),
              Text('Restart',
                  style: TextStyle(color: AppTheme.darkTextMuted, fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

