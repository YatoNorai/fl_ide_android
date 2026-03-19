import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/build_provider.dart';

class BuildPanel extends StatelessWidget {
  final Project project;

  const BuildPanel({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    return Consumer<BuildProvider>(
      builder: (context, build, _) {
        return Column(
          children: [
            _BuildToolbar(project: project, buildProv: build),
            Expanded(child: _BuildOutput(result: build.result)),
          ],
        );
      },
    );
  }
}

class _BuildToolbar extends StatelessWidget {
  final Project project;
  final BuildProvider buildProv;

  const _BuildToolbar({required this.project, required this.buildProv});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ide = Theme.of(context).extension<IdeColors>()!;
    final result = buildProv.result;

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          // Status icon
          _StatusIcon(status: result.status),
          const SizedBox(width: 8),
          Text(
            _statusLabel(result.status),
            style: TextStyle(
              color: _statusColor(result.status, cs, ide),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          // APK found
          if (result.apkPath != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ide.success.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: ide.success.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.android_rounded,
                      size: 13, color: ide.success),
                  const SizedBox(width: 4),
                  Text('APK ready',
                      style: TextStyle(
                          color: ide.success, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _InstallButton(apkPath: result.apkPath!),
            const SizedBox(width: 8),
          ],
          // Build button
          if (result.isRunning)
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: cs.error,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
              onPressed: context.read<BuildProvider>().cancel,
              icon: const Icon(Icons.stop_rounded, size: 14),
              label: const Text('Cancel', style: TextStyle(fontSize: 12)),
            )
          else
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: const Color(0xFF001849),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.play_arrow_rounded, size: 14),
              label: Text('Build ${project.sdk.displayName}'),
              onPressed: () =>
                  context.read<BuildProvider>().build(project),
            ),
        ],
      ),
    );
  }

  String _statusLabel(BuildStatus s) {
    switch (s) {
      case BuildStatus.idle:
        return 'Ready';
      case BuildStatus.running:
        return 'Building...';
      case BuildStatus.success:
        return 'Build successful';
      case BuildStatus.error:
        return 'Build failed';
    }
  }

  Color _statusColor(BuildStatus s, ColorScheme cs, IdeColors ide) {
    switch (s) {
      case BuildStatus.idle:
        return cs.onSurfaceVariant;
      case BuildStatus.running:
        return cs.primary;
      case BuildStatus.success:
        return ide.success;
      case BuildStatus.error:
        return cs.error;
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final BuildStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ide = Theme.of(context).extension<IdeColors>()!;
    switch (status) {
      case BuildStatus.idle:
        return Icon(Icons.circle_outlined,
            size: 14, color: cs.onSurfaceVariant);
      case BuildStatus.running:
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: cs.primary),
        );
      case BuildStatus.success:
        return Icon(Icons.check_circle_rounded,
            size: 14, color: ide.success);
      case BuildStatus.error:
        return Icon(Icons.error_rounded,
            size: 14, color: cs.error);
    }
  }
}

class _InstallButton extends StatelessWidget {
  final String apkPath;
  const _InstallButton({required this.apkPath});

  @override
  Widget build(BuildContext context) {
    final ide = Theme.of(context).extension<IdeColors>()!;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: ide.success.withValues(alpha: 0.15),
        foregroundColor: ide.success,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: ide.success, width: 0.5),
      ),
      onPressed: () => _installApk(context),
      icon: const Icon(Icons.install_mobile_rounded, size: 13),
      label: const Text('Install APK'),
    );
  }

  void _installApk(BuildContext context) {
    // pm install -r <apkPath>
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Installing $apkPath...'),
        action: SnackBarAction(label: 'OK', onPressed: () {}),
      ),
    );
    // The actual install happens via AppInstallerProvider (shell app)
    Navigator.of(context).pop();
  }
}

class _BuildOutput extends StatefulWidget {
  final BuildResult result;
  const _BuildOutput({required this.result});

  @override
  State<_BuildOutput> createState() => _BuildOutputState();
}

class _BuildOutputState extends State<_BuildOutput> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(_BuildOutput old) {
    super.didUpdateWidget(old);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      child: widget.result.output.isEmpty
          ? Center(
              child: Text('Press Build to start',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            )
          : Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                child: SelectableText(
                  widget.result.output,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ),
    );
  }
}
