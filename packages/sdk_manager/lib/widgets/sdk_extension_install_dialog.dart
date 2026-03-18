import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/sdk_extension.dart';

// ── Public entry point ────────────────────────────────────────────────────────

Future<void> showSdkExtensionInstallDialog(
  BuildContext context,
  SdkExtension ext,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _SdkInstallDialog(ext: ext),
  );
}

// ── Install phases ─────────────────────────────────────────────────────────────

enum _Phase { idle, downloading, installing, configuring, done, error }

class _StepState {
  final SdkExtStep step;
  bool done;
  bool active;
  String? output;

  _StepState({required this.step})
      : done = false,
        active = false;
}

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _SdkInstallDialog extends StatefulWidget {
  final SdkExtension ext;
  const _SdkInstallDialog({required this.ext});

  @override
  State<_SdkInstallDialog> createState() => _SdkInstallDialogState();
}

class _SdkInstallDialogState extends State<_SdkInstallDialog> {
  _Phase _phase = _Phase.idle;
  double _downloadProgress = 0.0;
  String _downloadLabel = '';
  late List<_StepState> _installStates;
  late List<_StepState> _configStates;
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _installStates =
        widget.ext.installSteps.map((s) => _StepState(step: s)).toList();
    _configStates =
        widget.ext.configSteps.map((s) => _StepState(step: s)).toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _resolve(String template, String downloadPath) {
    return template
        .replaceAll(r'$PREFIX', RuntimeEnvir.usrPath)
        .replaceAll(r'$HOME', RuntimeEnvir.homePath)
        .replaceAll(r'$ANDROID_HOME', RuntimeEnvir.androidSdkPath)
        .replaceAll(r'$DOWNLOAD_PATH', downloadPath);
  }

  Map<String, String> _env(String downloadPath) {
    final base = RuntimeEnvir.baseEnv;
    return {
      ...base,
      'PREFIX': RuntimeEnvir.usrPath,
      'DOWNLOAD_PATH': downloadPath,
      // Prepend flutter bin so config steps find the just-installed flutter
      'PATH': '${RuntimeEnvir.flutterPath}/bin:${base['PATH'] ?? ''}',
    };
  }

  Future<String> _runShell(String command, String downloadPath) async {
    final resolved = _resolve(command, downloadPath);
    debugPrint('[SdkInstall] shell: $resolved');
    final result = await Process.run(
      RuntimeEnvir.bashPath,
      ['-c', resolved],
      environment: _env(downloadPath),
      workingDirectory: RuntimeEnvir.homePath,
    );
    final stdout = result.stdout?.toString().trim() ?? '';
    final stderr = result.stderr?.toString().trim() ?? '';
    final exitCode = result.exitCode;
    if (stdout.isNotEmpty) debugPrint('[SdkInstall] stdout: $stdout');
    if (stderr.isNotEmpty) debugPrint('[SdkInstall] stderr: $stderr');
    debugPrint('[SdkInstall] exit code: $exitCode');
    return '$stdout$stderr'.trim();
  }

  String _extractCmd(SdkExtStep step, String downloadPath) {
    final dest = _resolve(step.dest ?? r'$PREFIX', downloadPath);
    debugPrint('[SdkInstall] extract type=${widget.ext.package.type} dest=$dest');
    switch (widget.ext.package.type) {
      case 'zip':
        return 'mkdir -p "$dest" && unzip -o "$downloadPath" -d "$dest"';
      case 'tar_gz':
        return 'mkdir -p "$dest" && tar xzf "$downloadPath" -C "$dest"';
      default:
        debugPrint('[SdkInstall] unknown package type: ${widget.ext.package.type}');
        return '';
    }
  }

  // ── Main install flow ──────────────────────────────────────────────────────

  Future<void> _startInstall() async {
    _cancelled = false;
    debugPrint('[SdkInstall] === starting install: ${widget.ext.displayName} ===');
    debugPrint('[SdkInstall] package url: ${widget.ext.package.url}');
    debugPrint('[SdkInstall] package type: ${widget.ext.package.type}');
    debugPrint('[SdkInstall] bash path: ${RuntimeEnvir.bashPath}');
    debugPrint('[SdkInstall] bash exists: ${File(RuntimeEnvir.bashPath).existsSync()}');
    debugPrint('[SdkInstall] PREFIX: ${RuntimeEnvir.usrPath}');
    debugPrint('[SdkInstall] HOME: ${RuntimeEnvir.homePath}');
    debugPrint('[SdkInstall] flutter path: ${RuntimeEnvir.flutterPath}');
    debugPrint('[SdkInstall] flutter binary exists: ${File('${RuntimeEnvir.flutterPath}/bin/flutter').existsSync()}');

    try {
      // ── Phase 1: Download ────────────────────────────────────────────────
      final tmpDir = '${RuntimeEnvir.filesPath}/tmp';
      await Directory(tmpDir).create(recursive: true);
      final downloadPath = '$tmpDir/${widget.ext.package.filename}';
      debugPrint('[SdkInstall] download path: $downloadPath');

      _set(() {
        _phase = _Phase.downloading;
        _downloadProgress = 0.0;
        _downloadLabel = 'Starting download...';
      });

      final dio = Dio();
      debugPrint('[SdkInstall] starting dio.download...');
      await dio.download(
        widget.ext.package.url,
        downloadPath,
        onReceiveProgress: (received, total) {
          if (_cancelled) throw Exception('cancelled');
          if (!mounted) return;
          _set(() {
            _downloadProgress = total > 0 ? received / total : 0;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = total > 0
                ? ' / ${(total / 1024 / 1024).toStringAsFixed(1)} MB'
                : '';
            _downloadLabel = '$mb MB$totalMb';
          });
        },
        options: Options(followRedirects: true, maxRedirects: 10),
      );
      debugPrint('[SdkInstall] download complete. file exists: ${File(downloadPath).existsSync()}');
      debugPrint('[SdkInstall] file size: ${File(downloadPath).existsSync() ? File(downloadPath).lengthSync() : 0} bytes');

      if (_cancelled) return;

      // ── Phase 2: Install steps ──────────────────────────────────────────
      debugPrint('[SdkInstall] === phase 2: install (${_installStates.length} steps) ===');
      _set(() => _phase = _Phase.installing);
      for (final state in _installStates) {
        if (_cancelled) return;
        debugPrint('[SdkInstall] install step: "${state.step.description}" type=${state.step.type}');
        _set(() => state.active = true);

        final String cmd;
        if (state.step.type == 'extract') {
          cmd = _extractCmd(state.step, downloadPath);
        } else {
          cmd = state.step.command ?? '';
        }

        if (cmd.isNotEmpty) {
          final out = await _runShell(cmd, downloadPath);
          state.output = out;
        } else {
          debugPrint('[SdkInstall] skipping empty command');
        }

        _set(() {
          state.active = false;
          state.done = true;
        });
        debugPrint('[SdkInstall] install step done: "${state.step.description}"');
      }

      // ── Phase 3: Config steps ───────────────────────────────────────────
      debugPrint('[SdkInstall] === phase 3: configure (${_configStates.length} steps) ===');
      _set(() => _phase = _Phase.configuring);
      for (final state in _configStates) {
        if (_cancelled) return;
        debugPrint('[SdkInstall] config step: "${state.step.description}"');
        _set(() => state.active = true);

        final cmd = state.step.command ?? '';
        if (cmd.isNotEmpty) {
          final out = await _runShell(cmd, downloadPath);
          state.output = out;
        } else {
          debugPrint('[SdkInstall] skipping empty config command');
        }

        _set(() {
          state.active = false;
          state.done = true;
        });
        debugPrint('[SdkInstall] config step done: "${state.step.description}"');
      }

      // ── Cleanup temp file ───────────────────────────────────────────────
      try {
        await File(downloadPath).delete();
        debugPrint('[SdkInstall] temp file deleted');
      } catch (e) {
        debugPrint('[SdkInstall] could not delete temp file: $e');
      }

      debugPrint('[SdkInstall] === install complete ===');
      _set(() => _phase = _Phase.done);
    } on DioException catch (e) {
      if (_cancelled) return;
      debugPrint('[SdkInstall] DioException: ${e.type} | ${e.message} | ${e.error}');
      debugPrint('[SdkInstall] response: ${e.response?.statusCode} ${e.response?.data}');
      _set(() {
        _phase = _Phase.error;
        _error = 'Download failed: ${e.message}';
      });
    } catch (e, stack) {
      if (_cancelled) return;
      debugPrint('[SdkInstall] unexpected error: $e');
      debugPrint('[SdkInstall] stack: $stack');
      _set(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  void _set(VoidCallback fn) {
    if (mounted) setState(fn);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isRunning =
        _phase != _Phase.idle && _phase != _Phase.done && _phase != _Phase.error;

    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      title: _buildTitle(cs),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_phase == _Phase.idle) _buildIdleInfo(cs),
              if (_phase != _Phase.idle) ...[
                _PhaseSection(
                  label: 'Download',
                  icon: Icons.download_rounded,
                  isActive: _phase == _Phase.downloading,
                  isDone: _phase.index > _Phase.downloading.index &&
                      _phase != _Phase.error,
                  cs: cs,
                  child: _phase == _Phase.downloading ||
                          _phase.index > _Phase.downloading.index
                      ? _DownloadProgress(
                          progress: _downloadProgress,
                          label: _downloadLabel,
                          done: _phase.index > _Phase.downloading.index,
                          cs: cs,
                        )
                      : null,
                ),
                const SizedBox(height: 8),
                _PhaseSection(
                  label: 'Install',
                  icon: Icons.install_mobile_rounded,
                  isActive: _phase == _Phase.installing,
                  isDone: _phase.index > _Phase.installing.index &&
                      _phase != _Phase.error,
                  cs: cs,
                  child: _phase.index >= _Phase.installing.index
                      ? _StepList(states: _installStates, cs: cs)
                      : null,
                ),
                const SizedBox(height: 8),
                _PhaseSection(
                  label: 'Configure',
                  icon: Icons.tune_rounded,
                  isActive: _phase == _Phase.configuring,
                  isDone: _phase == _Phase.done,
                  cs: cs,
                  child: _phase.index >= _Phase.configuring.index
                      ? _StepList(states: _configStates, cs: cs)
                      : null,
                ),
              ],
              if (_phase == _Phase.done) ...[
                const SizedBox(height: 16),
                _SuccessBanner(cs: cs),
              ],
              if (_phase == _Phase.error) ...[
                const SizedBox(height: 12),
                _ErrorBanner(message: _error ?? 'Unknown error', cs: cs),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
      actions: [
        if (_phase == _Phase.idle || _phase == _Phase.error)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel',
                style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
          ),
        if (_phase == _Phase.done || _phase == _Phase.error)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        if (isRunning)
          TextButton(
            onPressed: () {
              _cancelled = true;
              Navigator.of(context).pop();
            },
            child: Text('Cancel',
                style: TextStyle(color: cs.error)),
          ),
        if (_phase == _Phase.idle)
          FilledButton.icon(
            onPressed: _startInstall,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Install'),
          ),
        if (isRunning)
          FilledButton(
            onPressed: null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.onPrimary),
                ),
                const SizedBox(width: 8),
                const Text('Installing...'),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTitle(ColorScheme cs) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.extension_rounded, size: 20, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.ext.displayName,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              Text(
                'v${widget.ext.sdkVersion} · ${widget.ext.package.arch}',
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.55),
                    fontWeight: FontWeight.normal),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIdleInfo(ColorScheme cs) {
    final pkg = widget.ext.package;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.ext.description,
            style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.7),
                height: 1.5)),
        const SizedBox(height: 12),
        _InfoRow(
          icon: Icons.inventory_2_outlined,
          label: pkg.type.toUpperCase(),
          value: pkg.sizeMb != null ? '~${pkg.sizeMb!.toInt()} MB' : '',
          cs: cs,
        ),
        const SizedBox(height: 6),
        _InfoRow(
          icon: Icons.person_outline_rounded,
          label: 'Package by',
          value: widget.ext.packageAuthor.name,
          cs: cs,
        ),
        const SizedBox(height: 6),
        _InfoRow(
          icon: Icons.edit_outlined,
          label: 'Extension by',
          value:
              '${widget.ext.jsonAuthor.name} · ${widget.ext.jsonAuthor.date}',
          cs: cs,
        ),
        const SizedBox(height: 8),
        Divider(color: cs.outline.withValues(alpha: 0.15)),
        const SizedBox(height: 4),
        Text(
          '${widget.ext.installSteps.length} install step(s) · ${widget.ext.configSteps.length} config step(s)',
          style: TextStyle(
              fontSize: 12, color: cs.onSurface.withValues(alpha: 0.45)),
        ),
      ],
    );
  }
}

// ── Phase section ─────────────────────────────────────────────────────────────

class _PhaseSection extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final bool isDone;
  final ColorScheme cs;
  final Widget? child;

  const _PhaseSection({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.isDone,
    required this.cs,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final Widget iconWidget;

    if (isDone) {
      iconColor = cs.primary;
      iconWidget = Icon(Icons.check_circle_rounded, size: 18, color: iconColor);
    } else if (isActive) {
      iconColor = cs.primary;
      iconWidget = SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(
            strokeWidth: 2.5, color: iconColor),
      );
    } else {
      iconColor = cs.onSurface.withValues(alpha: 0.3);
      iconWidget = Icon(icon, size: 18, color: iconColor);
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive || isDone
            ? cs.primaryContainer.withValues(alpha: isDone ? 0.25 : 0.4)
            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? cs.primary.withValues(alpha: 0.3)
              : isDone
                  ? cs.primary.withValues(alpha: 0.15)
                  : cs.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              iconWidget,
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive || isDone
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
          if (child != null) ...[
            const SizedBox(height: 8),
            child!,
          ],
        ],
      ),
    );
  }
}

// ── Download progress ─────────────────────────────────────────────────────────

class _DownloadProgress extends StatelessWidget {
  final double progress;
  final String label;
  final bool done;
  final ColorScheme cs;

  const _DownloadProgress(
      {required this.progress,
      required this.label,
      required this.done,
      required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: done ? 1.0 : (progress > 0 ? progress : null),
            backgroundColor: cs.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(cs.primary),
            minHeight: 5,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              done ? 'Complete' : label,
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55)),
            ),
            Text(
              done ? '100%' : '${(progress * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.primary),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Step list ─────────────────────────────────────────────────────────────────

class _StepList extends StatelessWidget {
  final List<_StepState> states;
  final ColorScheme cs;

  const _StepList({required this.states, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: states.map((s) {
        final Widget leading;
        if (s.done) {
          leading =
              Icon(Icons.check_rounded, size: 14, color: cs.primary);
        } else if (s.active) {
          leading = SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
          );
        } else {
          leading = Icon(Icons.radio_button_unchecked_rounded,
              size: 14, color: cs.onSurface.withValues(alpha: 0.3));
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: SizedBox(width: 16, height: 14, child: leading),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.step.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: s.done || s.active
                        ? cs.onSurface.withValues(alpha: 0.85)
                        : cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Success / Error banners ───────────────────────────────────────────────────

class _SuccessBanner extends StatelessWidget {
  final ColorScheme cs;
  const _SuccessBanner({required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Installation complete! Restart the terminal to use the SDK.',
              style: TextStyle(
                  fontSize: 12,
                  color: cs.primary,
                  fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final ColorScheme cs;
  const _ErrorBanner({required this.message, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 20, color: cs.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(fontSize: 12, color: cs.error),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.cs});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: cs.onSurface.withValues(alpha: 0.45)),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
              fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.8)),
        ),
      ],
    );
  }
}
