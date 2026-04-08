import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/sdk_extension.dart';

// ── Public entry points ───────────────────────────────────────────────────────

Future<void> showSdkExtensionInstallDialog(
  BuildContext context,
  SdkExtension ext,
) {
  return showThemedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RepaintBoundary(
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child:
    _SdkInstallDialog(ext: ext, uninstall: false))),
  );
}

Future<void> showSdkExtensionUninstallDialog(
  BuildContext context,
  SdkExtension ext,
) {
  return showThemedDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => RepaintBoundary(
        child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: _SdkInstallDialog(ext: ext, uninstall: true))),
  );
}

// ── Install phases ─────────────────────────────────────────────────────────────

enum _Phase { idle, downloading, installing, configuring, uninstalling, cleanup, done, error }

class _StepState {
  final SdkExtStep step;
  bool done;
  bool active;
  String? output;
  final List<String> liveLines = [];

  _StepState({required this.step})
      : done = false,
        active = false;
}

// ── Dialog widget ─────────────────────────────────────────────────────────────

class _SdkInstallDialog extends StatefulWidget {
  final SdkExtension ext;
  final bool uninstall;
  const _SdkInstallDialog({required this.ext, required this.uninstall});

  @override
  State<_SdkInstallDialog> createState() => _SdkInstallDialogState();
}

class _SdkInstallDialogState extends State<_SdkInstallDialog> {
  _Phase _phase = _Phase.idle;
  double _downloadProgress = 0.0;
  String _downloadLabel = '';
  late List<_StepState> _installStates;
  late List<_StepState> _configStates;
  late List<_StepState> _cleanupStates;
  late List<_StepState> _uninstallStates;
  String? _error;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _installStates =
        widget.ext.installSteps.map((s) => _StepState(step: s)).toList();
    _configStates =
        widget.ext.configSteps.map((s) => _StepState(step: s)).toList();
    _cleanupStates =
        widget.ext.cleanupSteps.map((s) => _StepState(step: s)).toList();
    _uninstallStates =
        widget.ext.uninstallSteps.map((s) => _StepState(step: s)).toList();
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
    final androidHome = RuntimeEnvir.androidSdkPath;
    return {
      ...base,
      'PREFIX': RuntimeEnvir.usrPath,
      'ANDROID_HOME': androidHome,
      'DOWNLOAD_PATH': downloadPath,
      // Include flutter bin, android cmdline-tools and platform-tools so every
      // step can call sdkmanager/adb without needing "export PATH=..." inline.
      'PATH': '${RuntimeEnvir.flutterPath}/bin'
          ':$androidHome/cmdline-tools/latest/bin'
          ':$androidHome/platform-tools'
          ':${base['PATH'] ?? ''}',
    };
  }

  /// Runs [command] in bash, streaming stdout+stderr line-by-line.
  /// [onLine] is called on every new line so the UI can update in real-time.
  Future<String> _runShell(
    String command,
    String downloadPath, {
    void Function(String line)? onLine,
  }) async {
    final resolved = _resolve(command, downloadPath);
    debugPrint('[SdkInstall] shell: $resolved');

    final process = await Process.start(
      RuntimeEnvir.bashPath,
      ['-c', resolved],
      environment: _env(downloadPath),
      workingDirectory: RuntimeEnvir.homePath,
    );

    final buffer = StringBuffer();

    Future<void> consume(Stream<List<int>> stream) async {
      await for (final chunk in stream) {
        final text = String.fromCharCodes(chunk);
        buffer.write(text);
        for (final line in text.split('\n')) {
          final l = line.trim();
          if (l.isNotEmpty) {
            debugPrint('[SdkInstall] $l');
            onLine?.call(l);
          }
        }
      }
    }

    await Future.wait([consume(process.stdout), consume(process.stderr)]);
    final exitCode = await process.exitCode;
    debugPrint('[SdkInstall] exit: $exitCode');

    final output = buffer.toString().trim();
    if (exitCode != 0) {
      throw Exception(
          'Step failed (exit $exitCode)${output.isNotEmpty ? ':\n$output' : ''}');
    }
    return output;
  }

  Future<void> _runSteps(List<_StepState> states, String downloadPath) async {
    for (final state in states) {
      if (_cancelled) return;
      _set(() {
        state.active = true;
        state.liveLines.clear();
      });
      final cmd = state.step.command ?? '';
      if (cmd.isNotEmpty) {
        state.output = await _runShell(cmd, downloadPath, onLine: (line) {
          _set(() {
            state.liveLines.add(line);
            if (state.liveLines.length > 6) state.liveLines.removeAt(0);
          });
        });
      }
      _set(() {
        state.active = false;
        state.done = true;
      });
    }
  }

  String _extractCmd(SdkExtStep step, String downloadPath) {
    final dest = _resolve(step.dest ?? r'$PREFIX', downloadPath);
    switch (widget.ext.package.type) {
      case 'zip':
        return 'mkdir -p "$dest" && unzip -o "$downloadPath" -d "$dest"';
      case 'tar_gz':
        return 'mkdir -p "$dest" && tar xzf "$downloadPath" -C "$dest"';
      default:
        return '';
    }
  }

  // ── Cleanup on error ───────────────────────────────────────────────────────

  Future<void> _runCleanup(String downloadPath) async {
    _set(() => _phase = _Phase.cleanup);
    // Delete temp file
    try {
      final f = File(downloadPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    // Run JSON-defined cleanup steps
    if (widget.ext.cleanupSteps.isNotEmpty) {
      for (final state in _cleanupStates) {
        state.done = false;
        state.active = false;
      }
      await _runSteps(_cleanupStates, downloadPath);
    } else {
      // Generic fallback for deb: try dpkg --purge
      if (widget.ext.package.type == 'deb') {
        final pkgName = widget.ext.package.filename
            .split('_')
            .first
            .toLowerCase();
        await _runShell(
            'dpkg --purge $pkgName 2>&1 || apt-get remove --purge -y $pkgName 2>&1 || true',
            downloadPath);
      }
    }
  }

  // ── Main install flow ──────────────────────────────────────────────────────

  bool get _needsDownload =>
      widget.ext.package.type != 'pkg' && widget.ext.package.url.isNotEmpty;

  Future<void> _startInstall() async {
    _cancelled = false;
    final tmpDir = '${RuntimeEnvir.filesPath}/tmp';
    await Directory(tmpDir).create(recursive: true);
    final downloadPath = _needsDownload
        ? '$tmpDir/${widget.ext.package.filename}'
        : '';

    try {
      // Phase 1: Download (skipped for pkg-type SDKs)
      if (_needsDownload) {
        _set(() {
          _phase = _Phase.downloading;
          _downloadProgress = 0.0;
          _downloadLabel = 'Starting download...';
        });

        final dio = Dio();
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

        if (_cancelled) return;
      }

      // Phase 2: Install steps
      _set(() => _phase = _Phase.installing);
      for (final state in _installStates) {
        if (_cancelled) return;
        _set(() {
          state.active = true;
          state.liveLines.clear();
        });
        final String cmd;
        if (state.step.type == 'extract') {
          cmd = _extractCmd(state.step, downloadPath);
        } else {
          cmd = state.step.command ?? '';
        }
        if (cmd.isNotEmpty) {
          state.output = await _runShell(cmd, downloadPath, onLine: (line) {
            _set(() {
              state.liveLines.add(line);
              if (state.liveLines.length > 6) state.liveLines.removeAt(0);
            });
          });
        }
        _set(() {
          state.active = false;
          state.done = true;
        });
      }

      // Phase 3: Config steps
      _set(() => _phase = _Phase.configuring);
      await _runSteps(_configStates, downloadPath);

      // Cleanup temp file on success
      if (downloadPath.isNotEmpty) {
        try { await File(downloadPath).delete(); } catch (_) {}
      }

      _set(() => _phase = _Phase.done);
    } on DioException catch (e) {
      if (_cancelled) return;
      debugPrint('[SdkInstall] DioException: ${e.message}');
      await _runCleanup(downloadPath);
      _set(() {
        _phase = _Phase.error;
        _error = 'Download failed: ${e.message}';
      });
    } catch (e, stack) {
      if (_cancelled) return;
      debugPrint('[SdkInstall] error: $e\n$stack');
      await _runCleanup(downloadPath);
      _set(() {
        _phase = _Phase.error;
        _error = e.toString();
      });
    }
  }

  // ── Uninstall flow ─────────────────────────────────────────────────────────

  Future<void> _startUninstall() async {
    _cancelled = false;
    const downloadPath = '';
    _set(() => _phase = _Phase.uninstalling);

    try {
      if (widget.ext.uninstallSteps.isNotEmpty) {
        await _runSteps(_uninstallStates, downloadPath);
      } else {
        // Generic fallback
        if (widget.ext.package.type == 'deb') {
          final pkgName = widget.ext.package.filename
              .split('_')
              .first
              .toLowerCase();
          await _runShell(
              'dpkg --purge $pkgName 2>&1 || apt-get remove --purge -y $pkgName 2>&1 || true',
              downloadPath);
        }
      }
      _set(() => _phase = _Phase.done);
    } catch (e) {
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
    final isRunning = _phase != _Phase.idle &&
        _phase != _Phase.done &&
        _phase != _Phase.error;

    return AlertDialog(
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20),side: BorderSide(color: Colors.grey, width: 0.2)),
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
              if (!widget.uninstall && _phase != _Phase.idle) ...[
                if (_needsDownload) ...[
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
                ],
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
                if (_phase == _Phase.cleanup) ...[
                  const SizedBox(height: 8),
                  _PhaseSection(
                    label: 'Cleanup (reversing on error)',
                    icon: Icons.cleaning_services_rounded,
                    isActive: true,
                    isDone: false,
                    cs: cs,
                    child: _StepList(states: _cleanupStates, cs: cs),
                  ),
                ],
              ],
              if (widget.uninstall && _phase != _Phase.idle) ...[
                _PhaseSection(
                  label: 'Uninstall',
                  icon: Icons.delete_outline_rounded,
                  isActive: _phase == _Phase.uninstalling,
                  isDone: _phase == _Phase.done,
                  cs: cs,
                  child: _phase.index >= _Phase.uninstalling.index
                      ? _StepList(states: _uninstallStates, cs: cs)
                      : null,
                ),
              ],
              if (_phase == _Phase.done) ...[
                const SizedBox(height: 16),
                _SuccessBanner(
                  message: widget.uninstall
                      ? 'Uninstalled successfully. Restart the terminal to apply changes.'
                      : 'Installation complete! Restart the terminal to use the SDK.',
                  cs: cs,
                ),
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
                style:
                    TextStyle(color: cs.onSurface.withValues(alpha: 0.6))),
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
            child: Text('Cancel', style: TextStyle(color: cs.error)),
          ),
        if (_phase == _Phase.idle)
          FilledButton.icon(
            onPressed: widget.uninstall ? _startUninstall : _startInstall,
            icon: Icon(
              widget.uninstall
                  ? Icons.delete_outline_rounded
                  : Icons.download_rounded,
              size: 16,
            ),
            style: widget.uninstall
                ? FilledButton.styleFrom(backgroundColor: cs.error)
                : null,
            label: Text(widget.uninstall ? 'Uninstall' : 'Install'),
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
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                ),
                const SizedBox(width: 8),
                Text(widget.uninstall ? 'Uninstalling...' : 'Installing...'),
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
            color: widget.uninstall
                ? cs.errorContainer
                : cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            widget.uninstall
                ? Icons.delete_outline_rounded
                : Icons.extension_rounded,
            size: 20,
            color: widget.uninstall ? cs.error : cs.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.uninstall
                    ? 'Uninstall ${widget.ext.displayName}'
                    : widget.ext.displayName,
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface),
              ),
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
        Text(
          widget.uninstall
              ? 'This will remove ${widget.ext.displayName} from your device.'
              : widget.ext.description,
          style: TextStyle(
              fontSize: 13,
              color: cs.onSurface.withValues(alpha: 0.7),
              height: 1.5),
        ),
        const SizedBox(height: 12),
        if (!widget.uninstall) ...[
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
            value: '${widget.ext.jsonAuthor.name} · ${widget.ext.jsonAuthor.date}',
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
        child: CircularProgressIndicator(strokeWidth: 2.5, color: iconColor),
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
            Text(done ? 'Complete' : label,
                style: TextStyle(
                    fontSize: 11, color: cs.onSurface.withValues(alpha: 0.55))),
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
          leading = Icon(Icons.check_rounded, size: 14, color: cs.primary);
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
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
              if (s.active && s.liveLines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 24, top: 4),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      s.liveLines.join('\n'),
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withValues(alpha: 0.6),
                        height: 1.4,
                      ),
                      maxLines: 6,
                      overflow: TextOverflow.ellipsis,
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
  final String message;
  final ColorScheme cs;
  const _SuccessBanner({required this.message, required this.cs});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.primary,
                    fontWeight: FontWeight.w500)),
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
            child: Text(message,
                style: TextStyle(fontSize: 12, color: cs.error)),
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
        Text(label,
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
        const SizedBox(width: 6),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8))),
      ],
    );
  }
}
