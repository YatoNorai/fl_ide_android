import 'package:flutter/material.dart';
import 'package:core/core.dart';
import 'package:provider/provider.dart';

import '../providers/rootfs_provider.dart';

class DownloadBootstrapScreen extends StatefulWidget {
  final VoidCallback onReady;
  const DownloadBootstrapScreen({super.key, required this.onReady});

  @override
  State<DownloadBootstrapScreen> createState() =>
      _DownloadBootstrapScreenState();
}

class _DownloadBootstrapScreenState extends State<DownloadBootstrapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<RootfsProvider>().state == RootfsState.ready) {
        widget.onReady();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<RootfsProvider>(
      builder: (context, rootfs, _) {
        if (rootfs.state == RootfsState.ready) {
          WidgetsBinding.instance
              .addPostFrameCallback((_) => widget.onReady());
        }

        return Scaffold(
          backgroundColor: AppTheme.darkBg,
          body: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title bar (like AndroidIDE home)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 16),
                    child: Text('FL IDE',
                        style: TextStyle(
                            color: AppTheme.darkText,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _SetupContent(rootfs: rootfs),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SetupContent extends StatelessWidget {
  final RootfsProvider rootfs;
  const _SetupContent({required this.rootfs});

  @override
  Widget build(BuildContext context) {
    return switch (rootfs.state) {
      RootfsState.notInstalled => _NotInstalled(
          onInstall: context.read<RootfsProvider>().downloadAndInstall),
      RootfsState.error => _ErrorState(
          error: rootfs.error ?? 'Unknown error',
          onRetry: context.read<RootfsProvider>().retry),
      RootfsState.ready => const _ReadyState(),
      _ => _ProgressState(
          message: rootfs.statusMessage,
          progress: rootfs.progress,
          isDownloading: rootfs.state == RootfsState.downloading),
    };
  }
}

class _NotInstalled extends StatelessWidget {
  final VoidCallback onInstall;
  const _NotInstalled({required this.onInstall});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Icon badge
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: AppTheme.darkSurface,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.download_for_offline_outlined,
              size: 36, color: AppTheme.darkText),
        ),
        const SizedBox(height: 24),
        const Text("First-time setup",
            style: TextStyle(
                color: AppTheme.darkText,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        const Text(
          "FL IDE needs to download a Linux environment (~70 MB). This only happens once.",
          style: TextStyle(
              color: AppTheme.darkTextMuted, fontSize: 14, height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onInstall,
            child: const Text('Install Environment'),
          ),
        ),
      ],
    );
  }
}

class _ProgressState extends StatelessWidget {
  final String message;
  final double progress;
  final bool isDownloading;

  const _ProgressState({
    required this.message,
    required this.progress,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: AppTheme.darkSurface,
            shape: BoxShape.circle,
          ),
          child: const Center(
            child: SizedBox(
              width: 36,
              height: 36,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: AppTheme.darkAccent),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text(
          isDownloading ? 'Downloading...' : 'Extracting...',
          style: const TextStyle(
              color: AppTheme.darkText,
              fontSize: 22,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(message,
            style: const TextStyle(
                color: AppTheme.darkTextMuted, fontSize: 14),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress > 0 ? progress : null,
            backgroundColor: AppTheme.darkSurface,
            valueColor:
                const AlwaysStoppedAnimation(AppTheme.darkAccent),
            minHeight: 4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${(progress * 100).toStringAsFixed(0)}%',
          style: const TextStyle(
              color: AppTheme.darkAccent,
              fontSize: 14,
              fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;

  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline,
            size: 48, color: AppTheme.darkError),
        const SizedBox(height: 16),
        const Text('Installation Failed',
            style: TextStyle(
                color: AppTheme.darkText,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(error,
            style: const TextStyle(
                color: AppTheme.darkTextMuted, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _ReadyState extends StatelessWidget {
  const _ReadyState();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.check_circle_outline,
            size: 48, color: AppTheme.darkSuccess),
        SizedBox(height: 16),
        Text('Environment Ready',
            style: TextStyle(
                color: AppTheme.darkText,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        Text('Linux environment is installed.',
            style: TextStyle(color: AppTheme.darkTextMuted, fontSize: 14)),
      ],
    );
  }
}
