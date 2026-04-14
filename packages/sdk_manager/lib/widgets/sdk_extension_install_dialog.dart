import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../models/sdk_extension.dart';

// ── Public entry points ───────────────────────────────────────────────────────
//
// Cada função cria um [ValueNotifier] local para as actions do rodapé e o
// repassa tanto para [showThemedDialog] (via actionsListenable) quanto para
// o corpo do diálogo (via actionsNotifier), que o atualiza sempre que seu
// estado interno muda.

Future<void> showSdkExtensionInstallDialog(
  BuildContext context,
  SdkExtension ext,
) {
  final actionsNotifier = ValueNotifier<List<Widget>>([]);
  return showThemedDialog<void>(
    context: context,
    title: ext.displayName,
    barrierDismissible: false,
    maxWidth: 420,
    maxHeight: 580,
    actionsListenable: actionsNotifier,
    builder: (_) => _SdkInstallBody(
      ext: ext,
      uninstall: false,
      actionsNotifier: actionsNotifier,
    ),
  );
}

Future<void> showSdkExtensionUninstallDialog(
  BuildContext context,
  SdkExtension ext,
) {
  final actionsNotifier = ValueNotifier<List<Widget>>([]);
  return showThemedDialog<void>(
    context: context,
    title: 'Uninstall ${ext.displayName}',
    barrierDismissible: false,
    maxWidth: 420,
    maxHeight: 580,
    actionsListenable: actionsNotifier,
    builder: (_) => _SdkInstallBody(
      ext: ext,
      uninstall: true,
      actionsNotifier: actionsNotifier,
    ),
  );
}

// ── Install phases ────────────────────────────────────────────────────────────

enum _Phase {
  idle,
  downloading,
  installing,
  configuring,
  uninstalling,
  cleanup,
  done,
  error,
}

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

// ── Body widget ───────────────────────────────────────────────────────────────
//
// Retorna apenas o conteúdo — sem AlertDialog. O chrome do diálogo
// (backdrop, card, título, rodapé de actions) é responsabilidade do
// showThemedDialog que envolve este widget.

class _SdkInstallBody extends StatefulWidget {
  final SdkExtension ext;
  final bool uninstall;

  /// Notifier compartilhado com [showThemedDialog] via actionsListenable.
  /// Este widget o atualiza sempre que [_phase] muda.
  final ValueNotifier<List<Widget>> actionsNotifier;

  const _SdkInstallBody({
    required this.ext,
    required this.uninstall,
    required this.actionsNotifier,
  });

  @override
  State<_SdkInstallBody> createState() => _SdkInstallBodyState();
}

class _SdkInstallBodyState extends State<_SdkInstallBody> {
  _Phase _phase = _Phase.idle;
  double _downloadProgress = 0.0;
  String _downloadLabel = '';
  late List<_StepState> _installStates;
  late List<_StepState> _configStates;
  late List<_StepState> _cleanupStates;
  late List<_StepState> _uninstallStates;
  String? _error;
  bool _cancelled = false;

  // Throttle download progress setState to once per 100 ms.
  Timer? _progressTimer;
  double _pendingProgress = 0.0;
  String _pendingLabel = '';

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

    // Popula as actions iniciais após o primeiro frame estar pronto.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActions());
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  // ── Actions notifier ───────────────────────────────────────────────────────
  //
  // Recria a lista de widgets e empurra para o ValueNotifier.
  // Chamado após cada mudança de estado via _set().

  void _updateActions() {
    if (!mounted) return;
    final cs = Theme.of(context).colorScheme;
    final isRunning = _phase != _Phase.idle &&
        _phase != _Phase.done &&
        _phase != _Phase.error;

    widget.actionsNotifier.value = [
      // "Cancel" visível no estado idle e em caso de erro
      if (_phase == _Phase.idle || _phase == _Phase.error)
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ),

      // "Close" visível ao concluir (sucesso ou erro)
      if (_phase == _Phase.done || _phase == _Phase.error)
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),

      // "Cancel" vermelho durante execução
      if (isRunning)
        TextButton(
          onPressed: () {
            _cancelled = true;
            Navigator.of(context).pop();
          },
          child: Text('Cancel', style: TextStyle(color: cs.error)),
        ),

      // Botão principal no estado idle
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

      // Botão desabilitado com spinner durante execução
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
              Text(widget.uninstall ? 'Uninstalling...' : 'Installing...'),
            ],
          ),
        ),
    ];
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
      'PATH': '${RuntimeEnvir.flutterPath}/bin'
          ':$androidHome/cmdline-tools/latest/bin'
          ':$androidHome/platform-tools'
          ':${base['PATH'] ?? ''}',
    };
  }

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
        // Use pigz (parallel gzip) when available for faster decompression;
        // fall back to plain tar xzf otherwise.
        return 'mkdir -p "$dest" && '
            '(command -v pigz >/dev/null 2>&1 '
            '  && tar --use-compress-program=pigz -xf "$downloadPath" -C "$dest" '
            '  || tar xzf "$downloadPath" -C "$dest")';
      default:
        return '';
    }
  }

  // ── Cleanup on error ───────────────────────────────────────────────────────

  Future<void> _runCleanup(String downloadPath) async {
    _set(() => _phase = _Phase.cleanup);
    try {
      final f = File(downloadPath);
      if (await f.exists()) await f.delete();
    } catch (_) {}

    if (widget.ext.cleanupSteps.isNotEmpty) {
      for (final state in _cleanupStates) {
        state.done = false;
        state.active = false;
      }
      await _runSteps(_cleanupStates, downloadPath);
    } else {
      if (widget.ext.package.type == 'deb') {
        final pkgName =
            widget.ext.package.filename.split('_').first.toLowerCase();
        await _runShell(
            'dpkg --purge $pkgName 2>&1 || apt-get remove --purge -y $pkgName 2>&1 || true',
            downloadPath);
      }
    }
  }

  // ── Install flow ───────────────────────────────────────────────────────────

  bool get _needsDownload =>
      widget.ext.package.type != 'pkg' && widget.ext.package.url.isNotEmpty;

  Future<void> _startInstall() async {
    _cancelled = false;
    final tmpDir = '${RuntimeEnvir.filesPath}/tmp';
    await Directory(tmpDir).create(recursive: true);
    final downloadPath =
        _needsDownload ? '$tmpDir/${widget.ext.package.filename}' : '';

    try {
      if (_needsDownload) {
        _set(() {
          _phase = _Phase.downloading;
          _downloadProgress = 0.0;
          _downloadLabel = 'Starting download...';
        });

        final dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 10),
        ));
        await dio.download(
          widget.ext.package.url,
          downloadPath,
          onReceiveProgress: (received, total) {
            if (_cancelled) throw Exception('cancelled');
            if (!mounted) return;
            // Update pending values immediately but only flush to setState
            // every 100 ms to avoid hundreds of rebuilds per second.
            _pendingProgress = total > 0 ? received / total : 0;
            final mb = (received / 1024 / 1024).toStringAsFixed(1);
            final totalMb = total > 0
                ? ' / ${(total / 1024 / 1024).toStringAsFixed(1)} MB'
                : '';
            _pendingLabel = '$mb MB$totalMb';
            _progressTimer ??= Timer(const Duration(milliseconds: 100), () {
              _progressTimer = null;
              if (mounted) {
                _set(() {
                  _downloadProgress = _pendingProgress;
                  _downloadLabel = _pendingLabel;
                });
              }
            });
          },
          options: Options(followRedirects: true, maxRedirects: 10),
        );
        _progressTimer?.cancel();
        _progressTimer = null;

        if (_cancelled) return;
      }

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

      _set(() => _phase = _Phase.configuring);
      await _runSteps(_configStates, downloadPath);

      if (downloadPath.isNotEmpty) {
        try {
          await File(downloadPath).delete();
        } catch (_) {}
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
        if (widget.ext.package.type == 'deb') {
          final pkgName =
              widget.ext.package.filename.split('_').first.toLowerCase();
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

  // ── State helper ───────────────────────────────────────────────────────────

  void _set(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
    // Agenda atualização das actions após o frame ser reconstruído,
    // garantindo que o context e o colorScheme estejam atualizados.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateActions());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cabeçalho compacto: ícone + versão ─────────────────────────────
          _buildHeader(cs),
          const SizedBox(height: 14),

          // ── Estado idle: descrição e metadados ─────────────────────────────
          if (_phase == _Phase.idle) _buildIdleInfo(cs),

          // ── Fases de instalação ────────────────────────────────────────────
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

          // ── Fases de desinstalação ─────────────────────────────────────────
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

          // ── Banners de resultado ───────────────────────────────────────────
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
    );
  }

  // ── Sub-widgets de build ───────────────────────────────────────────────────

  Widget _buildHeader(ColorScheme cs) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: widget.uninstall ? cs.errorContainer : cs.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            widget.uninstall
                ? Icons.delete_outline_rounded
                : Icons.extension_rounded,
            size: 18,
            color: widget.uninstall ? cs.error : cs.primary,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          'v${widget.ext.sdkVersion} · ${widget.ext.package.arch}',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.55),
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

  const _DownloadProgress({
    required this.progress,
    required this.label,
    required this.done,
    required this.cs,
  });

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
          leading = Icon(Icons.check_rounded, size: 14, color: cs.primary);
        } else if (s.active) {
          leading = SizedBox(
            width: 14,
            height: 14,
            child:
                CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color:
                          cs.surfaceContainerHighest.withValues(alpha: 0.5),
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
            child: Text(
              message,
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

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.cs,
  });

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