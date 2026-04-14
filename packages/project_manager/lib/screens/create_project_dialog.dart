import 'dart:async';
import 'dart:io';

import 'package:core/core.dart';
import 'package:fl_ide/l10n/app_strings.dart';
import 'package:fl_ide/providers/extensions_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../project_template.dart';
import '../providers/project_manager_provider.dart';

// Min SDK API level → Android version name
const _kMinSdkVersions = <int, String>{
  21: 'Android 5.0 (Lollipop)',
  23: 'Android 6.0 (Marshmallow)',
  24: 'Android 7.0 (Nougat)',
  26: 'Android 8.0 (Oreo)',
  28: 'Android 9 (Pie)',
  29: 'Android 10',
  30: 'Android 11',
  31: 'Android 12',
  33: 'Android 13 (Tiramisu)',
  34: 'Android 14',
  35: 'Android 15',
};

/// Full-screen project creation form.
class CreateProjectScreen extends StatefulWidget {
  /// If set, project is created on the remote host at this path.
  final String? remoteProjectsPath;
  final bool isSshActive;

  /// SDK names detected on the remote machine (from SshProvider.detectedSdks).
  final List<String> remoteSdkNames;

  /// True while SSH SDK detection is still running (show spinner instead of warning).
  final bool isSshDetecting;

  /// True when the remote SSH machine is Windows (affects shell command separator).
  final bool remoteIsWindows;

  /// Called instead of session.start() for SSH-backed terminal sessions.
  final Future<void> Function(TerminalSession)? sshTerminalSetup;

  const CreateProjectScreen({
    super.key,
    this.remoteProjectsPath,
    this.isSshActive = false,
    this.remoteSdkNames = const [],
    this.isSshDetecting = false,
    this.remoteIsWindows = false,
    this.sshTerminalSetup,
  });

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

// Keep old name for compat
typedef CreateProjectDialog = CreateProjectScreen;

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  late final TextEditingController _nameCtrl;
  final _packageCtrl = TextEditingController();
  SdkType? _selectedSdk;
  bool _creating = false;
  late final TerminalProvider _termProvider;
  Completer<void>? _createDone;
  ValueNotifier<double>? _progressNotifier;
  Timer? _progressTimer;

  // Android-specific options
  String _androidLanguage = 'Kotlin';
  int _androidMinSdk = 24;
  AndroidTemplate _androidTemplate = AndroidTemplate.emptyActivity;
  // Flutter-specific options
  FlutterTemplate _flutterTemplate = FlutterTemplate.counterApp;
  // React Native-specific options
  ReactNativeTemplate _rnTemplate = ReactNativeTemplate.blank;

  // SDKs that use a package/bundle identifier
  static const _pkgSdks = {
    SdkType.flutter,
    SdkType.androidSdk,
    SdkType.reactNative
  };

  /// Map a human-readable SDK name (from SSH detection) to SdkType.
  static SdkType? _sdkTypeFromName(String name) {
    switch (name) {
      case 'Flutter':
        return SdkType.flutter;
      case 'Android SDK':
        return SdkType.androidSdk;
      case 'Node.js':
        return SdkType.nodejs;
      case 'Python':
        return SdkType.python;
      default:
        return null;
    }
  }

  /// SDK types available for project creation on the remote machine.
  List<SdkType> get _remoteSdkTypes => widget.remoteSdkNames
      .map(_sdkTypeFromName)
      .whereType<SdkType>()
      .toList();

  bool get _supportsPackage =>
      _selectedSdk != null && _pkgSdks.contains(_selectedSdk);

  bool get _canCreate =>
      !_creating &&
      !widget.isSshDetecting &&
      _selectedSdk != null &&
      _nameCtrl.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _termProvider = TerminalProvider();
    _nameCtrl = TextEditingController(text: _nextAvailableName());
    _syncPackage();
    _nameCtrl.addListener(_syncPackage);
  }

  String _nextAvailableName() {
    if (widget.remoteProjectsPath != null) return 'application';
    const base = 'application';
    final dir = RuntimeEnvir.projectsPath;
    if (!Directory('$dir/$base').existsSync()) return base;
    for (int i = 1;; i++) {
      final candidate = '${base}_$i';
      if (!Directory('$dir/$candidate').existsSync()) return candidate;
    }
  }

  void _syncPackage() {
    final safe = _nameCtrl.text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]'), '_');
    final base = safe.isEmpty ? 'app' : safe;
    _packageCtrl.text = 'com.example.$base';
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_syncPackage);
    _nameCtrl.dispose();
    _packageCtrl.dispose();
    _progressTimer?.cancel();
    _progressNotifier?.dispose();
    _createDone?.complete();
    _termProvider.dispose();
    super.dispose();
  }

  // ── Pickers ────────────────────────────────────────────────────────────────

  Future<void> _pickLanguage() async {
    final result = await showThemedDialog<String>(
      context: context,
      title: 'Linguagem',
      items: const ['Kotlin', 'Java'],
      current: _androidLanguage,
      label: (v) => v,
    );
    if (result != null && mounted) {
      setState(() {
        _androidLanguage = result;
        if (result == 'Java' &&
            _androidTemplate == AndroidTemplate.emptyCompose) {
          _androidTemplate = AndroidTemplate.emptyActivity;
        }
      });
    }
  }

  Future<void> _pickMinSdk() async {
    final result = await showThemedDialog<int>(
      context: context,
      title: 'SDK Mínimo',
      items: _kMinSdkVersions.keys.toList(),
      current: _androidMinSdk,
      label: (v) => 'API $v  ·  ${_kMinSdkVersions[v] ?? ''}',
    );
    if (result != null && mounted) {
      setState(() => _androidMinSdk = result);
    }
  }

  Future<void> _pickSdk() async {
    final options = widget.isSshActive && _remoteSdkTypes.isNotEmpty
        ? _remoteSdkTypes
        : context.read<SdkManagerProvider>().installedSdks;
    if (options.isEmpty) return;

    final result = await showThemedDialog<SdkType>(
      context: context,
      title: AppStrings.of(context).selectSdk,
      maxHeight: 480,
      builder: (ctx) => _SdkPickerContent(
        options: options,
        selected: _selectedSdk,
        dialogContext: ctx,
      ),
    );
    if (result != null) setState(() => _selectedSdk = result);
  }

  // ── Progress dialog ────────────────────────────────────────────────────────

  void _showProgressDialog(String name) {
    _progressNotifier = ValueNotifier(0.0);
    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_progressNotifier == null) return;
      final remaining = 0.85 - _progressNotifier!.value;
      _progressNotifier!.value += remaining * 0.045;
    });
    showThemedDialog<void>(
      context: context,
      title: 'Criando projeto',
      barrierDismissible: false,
      maxWidth: 340,
      maxHeight: 300,
      builder: (_) => _ProgressContent(
        projectName: name,
        progressNotifier: _progressNotifier!,
      ),
    );
  }

  Future<void> _closeProgressDialog() async {
    _progressTimer?.cancel();
    _progressTimer = null;
    _progressNotifier?.value = 1.0;
    await Future.delayed(const Duration(milliseconds: 350));
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    _progressNotifier?.dispose();
    _progressNotifier = null;
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedSdk == null) return;
    setState(() => _creating = true);
    _showProgressDialog(name);

    final extProv = context.read<ExtensionsProvider>();
    final ext = extProv.availableSdks
        .where((e) => e.sdk == _selectedSdk!.name)
        .firstOrNull;
    final rawOverride = ext?.sdkConfig?.newProjectCmd ?? '';
    final overrideCmd = (rawOverride.isNotEmpty &&
            !(_selectedSdk == SdkType.reactNative &&
                (rawOverride.contains('--no-install') ||
                    rawOverride.contains('--template'))))
        ? rawOverride
        : null;

    final pm = context.read<ProjectManagerProvider>();
    final project = await pm.createProject(
      name: name,
      sdk: _selectedSdk!,
      newProjectCmd: overrideCmd,
      projectsBasePath: widget.remoteProjectsPath,
      remoteIsWindows: widget.remoteIsWindows,
      androidLanguage: _androidLanguage.toLowerCase(),
      androidMinSdk: _androidMinSdk,
      androidTemplate: _androidTemplate,
      flutterTemplate: _flutterTemplate,
      rnTemplate: _rnTemplate,
      runInTerminal: (script) async {
        await _termProvider.createSession(
          label: 'Criando $name',
          sshSetup: widget.sshTerminalSetup,
        );
        final session = _termProvider.active;
        if (session == null) return;

        _createDone = Completer<void>();
        final prev = session.onExit;
        session.onExit = (code) {
          prev?.call(code);
          if (!_createDone!.isCompleted) _createDone!.complete();
        };

        session.writeCommand('$script; exit');

        await _createDone!.future.timeout(
          const Duration(minutes: 8),
          onTimeout: () {
            if (!_createDone!.isCompleted) _createDone!.complete();
          },
        );
        _createDone = null;
      },
    );

    await _closeProgressDialog();
    if (!mounted) return;
    pm.openProject(project, isNew: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    final sdkMgr = context.watch<SdkManagerProvider>();
    final detecting = widget.isSshActive && widget.isSshDetecting;
    final noSdks = !detecting &&
        (widget.isSshActive
            ? _remoteSdkTypes.isEmpty
            : sdkMgr.installedSdks.isEmpty);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'L A Y E R',
          style: GoogleFonts.montserrat(
            fontSize: 18,
            fontWeight: FontWeight.w400,
            letterSpacing: 5.0,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Text(
              s.newProject,
              style: GoogleFonts.openSans(
                color: cs.onSurface,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          // ── Scrollable fields ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SSH indicator banner
                  if (widget.isSshActive &&
                      widget.remoteProjectsPath != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.secondaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.computer_rounded,
                              size: 16, color: cs.secondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'SSH: ${widget.remoteProjectsPath}',
                              style: GoogleFonts.openSans(
                                  color: cs.onSecondaryContainer, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // SDK selector
                  if (detecting)
                    _SdkDetectingTile()
                  else if (noSdks)
                    _NoSdkWarning()
                  else
                    _SdkSelectorTile(
                      selected: _selectedSdk,
                      onTap: _creating ? null : _pickSdk,
                    ),

                  const SizedBox(height: 16),

                  // Project name
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_creating,
                    style: GoogleFonts.openSans(
                        color: cs.onSurface, fontSize: 15),
                    decoration: _inputDeco(context, s.projectName),
                    onChanged: (_) => setState(() {}),
                  ),

                  // Package name (Flutter / Android / React Native only)
                  if (_supportsPackage) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _packageCtrl,
                      enabled: !_creating,
                      style: GoogleFonts.openSans(
                          color: cs.onSurface, fontSize: 15),
                      decoration: _inputDeco(context, s.packageName),
                    ),
                  ],

                  // ── Flutter template picker ────────────────────────────────
                  if (_selectedSdk == SdkType.flutter) ...[
                    const SizedBox(height: 20),
                    Text('Template',
                        style: GoogleFonts.openSans(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: FlutterTemplate.values.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final t = FlutterTemplate.values[i];
                          return _TemplateCard(
                            label: t.label,
                            description: t.description,
                            preview: _FlutterTemplatePreview(template: t),
                            selected: _flutterTemplate == t,
                            onTap: _creating
                                ? null
                                : () =>
                                    setState(() => _flutterTemplate = t),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── React Native template picker ───────────────────────────
                  if (_selectedSdk == SdkType.reactNative) ...[
                    const SizedBox(height: 20),
                    Text('Template',
                        style: GoogleFonts.openSans(
                            color: cs.onSurfaceVariant, fontSize: 12)),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: ReactNativeTemplate.values.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final t = ReactNativeTemplate.values[i];
                          return _TemplateCard(
                            label: t.label,
                            description: t.description,
                            preview: _RnTemplatePreview(template: t),
                            selected: _rnTemplate == t,
                            onTap: _creating
                                ? null
                                : () => setState(() => _rnTemplate = t),
                          );
                        },
                      ),
                    ),
                  ],

                  // ── Android-specific options ───────────────────────────────
                  if (_selectedSdk == SdkType.androidSdk) ...[
                    const SizedBox(height: 16),

                    // Language picker
                    _SelectTile(
                      label: 'Linguagem',
                      valueText: _androidLanguage,
                      enabled: !_creating,
                      onTap: _creating ? null : _pickLanguage,
                    ),

                    const SizedBox(height: 16),

                    // Min SDK picker
                    _SelectTile(
                      label: 'SDK Mínimo',
                      valueText:
                          'API $_androidMinSdk  ·  ${_kMinSdkVersions[_androidMinSdk] ?? ''}',
                      enabled: !_creating,
                      onTap: _creating ? null : _pickMinSdk,
                    ),

                    const SizedBox(height: 20),

                    // Template section header
                    Text(
                      'Template',
                      style: GoogleFonts.openSans(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Template picker (horizontal scroll)
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        clipBehavior: Clip.none,
                        itemCount: AndroidTemplate.values.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(width: 12),
                        itemBuilder: (ctx, i) {
                          final t = AndroidTemplate.values[i];
                          final disabled = _creating ||
                              (t == AndroidTemplate.emptyCompose &&
                                  _androidLanguage == 'Java');
                          return _TemplateCard(
                            label: t.label,
                            description: t.description,
                            preview: _AndroidTemplatePreview(template: t),
                            selected: _androidTemplate == t,
                            disabled: disabled,
                            disabledReason: 'Kotlin only',
                            onTap: disabled
                                ? null
                                : () =>
                                    setState(() => _androidTemplate = t),
                          );
                        },
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
      extendBody: true,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton(
              onPressed: _creating ? null : () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                backgroundColor: cs.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: _canCreate ? _create : null,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
              child: Text(_creating ? s.creating : s.createProject),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(BuildContext context, String label) {
    final cs = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

// ── SDK selector tile ─────────────────────────────────────────────────────────

class _SdkSelectorTile extends StatelessWidget {
  final SdkType? selected;
  final VoidCallback? onTap;

  const _SdkSelectorTile({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: cs.outline),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SDK',
                    style: GoogleFonts.openSans(
                        color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selected == null
                        ? AppStrings.of(context).selectSdk
                        : '${selected!.icon}  ${selected!.displayName}',
                    style: GoogleFonts.openSans(
                      color: selected == null
                          ? cs.onSurfaceVariant
                          : cs.onSurface,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── SDK picker content ────────────────────────────────────────────────────────
//
// Conteúdo do picker de SDK exibido dentro do showThemedDialog.
// Cada item mostra ícone, nome e descrição do SDK.

class _SdkPickerContent extends StatelessWidget {
  final List<SdkType> options;
  final SdkType? selected;
  final BuildContext dialogContext;

  const _SdkPickerContent({
    required this.options,
    required this.selected,
    required this.dialogContext,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: options.map((sdk) {
        final isSelected = sdk == selected;
        return InkWell(
          onTap: () => Navigator.of(dialogContext).pop(sdk),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Text(sdk.icon,
                    style: GoogleFonts.openSans(fontSize: 22)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        sdk.displayName,
                        style: GoogleFonts.openSans(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected ? cs.primary : cs.onSurface,
                        ),
                      ),
                      Text(
                        sdk.description,
                        style: GoogleFonts.openSans(
                          fontSize: 11,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Progress content ──────────────────────────────────────────────────────────
//
// Conteúdo da barra de progresso exibido dentro do showThemedDialog.
// Sem AlertDialog ou backdrop próprio — o chrome vem do showThemedDialog.

class _ProgressContent extends StatelessWidget {
  final String projectName;
  final ValueNotifier<double> progressNotifier;

  const _ProgressContent({
    required this.projectName,
    required this.progressNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: ValueListenableBuilder<double>(
        valueListenable: progressNotifier,
        builder: (_, progress, __) {
          final pct = (progress * 100).clamp(0, 100).round();
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.folder_open_rounded,
                      size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      projectName,
                      style: GoogleFonts.openSans(
                          color: cs.onSurfaceVariant, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(cs.primary),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$pct%',
                  style: GoogleFonts.openSans(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Select tile (opens themed picker) ────────────────────────────────────────

class _SelectTile extends StatelessWidget {
  final String label;
  final String valueText;
  final bool enabled;
  final VoidCallback? onTap;

  const _SelectTile({
    required this.label,
    required this.valueText,
    this.enabled = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(
              color: enabled ? cs.outline : cs.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.openSans(
                        color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    valueText,
                    style: GoogleFonts.openSans(
                      color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_drop_down_rounded,
                color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── Generic template card ─────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  final String label;
  final String description;
  final Widget preview;
  final bool selected;
  final bool disabled;
  final String? disabledReason;
  final VoidCallback? onTap;

  const _TemplateCard({
    required this.label,
    required this.description,
    required this.preview,
    required this.selected,
    this.disabled = false,
    this.disabledReason,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 140,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? cs.primary
                : disabled
                    ? cs.outlineVariant.withValues(alpha: 0.4)
                    : cs.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? cs.primaryContainer.withValues(alpha: 0.25)
              : cs.surfaceContainerLowest,
        ),
        child: Opacity(
          opacity: disabled ? 0.4 : 1.0,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Preview area (60%)
              Expanded(
                flex: 3,
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(13)),
                  child: preview,
                ),
              ),
              // Text area (40%)
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: GoogleFonts.openSans(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color:
                                    selected ? cs.primary : cs.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_circle_rounded,
                                size: 14, color: cs.primary),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        description,
                        style: GoogleFonts.openSans(
                          fontSize: 10,
                          color: cs.onSurfaceVariant,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (disabled && disabledReason != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          disabledReason!,
                          style: GoogleFonts.openSans(
                            fontSize: 9,
                            color: cs.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Template visual previews ──────────────────────────────────────────────────

// Shared helpers
Widget _previewBar({double width = 58, double height = 7, Color? color}) =>
    Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? const Color(0xFFBDBDBD),
        borderRadius: BorderRadius.circular(4),
      ),
    );

Widget _previewAppBar({Color color = const Color(0xFF1565C0)}) => Container(
      height: 24,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.8),
                  shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Container(
              width: 46,
              height: 5,
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(3))),
        ],
      ),
    );

Widget _previewBottomNavBar(
        {int tabs = 3, Color active = const Color(0xFF1565C0)}) =>
    Container(
      height: 32,
      decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, -2))
          ]),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: List.generate(tabs, (i) {
          final isActive = i == 0;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                  width: 20,
                  height: 12,
                  decoration: BoxDecoration(
                      color:
                          isActive ? active : const Color(0xFFBDBDBD),
                      borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 2),
              Container(
                  width: 24,
                  height: 4,
                  decoration: BoxDecoration(
                      color:
                          isActive ? active : const Color(0xFFBDBDBD),
                      borderRadius: BorderRadius.circular(2))),
            ],
          );
        }),
      ),
    );

// ── Android previews ──────────────────────────────────────────────────────────

class _AndroidTemplatePreview extends StatelessWidget {
  final AndroidTemplate template;
  const _AndroidTemplatePreview({required this.template});

  @override
  Widget build(BuildContext context) => switch (template) {
        AndroidTemplate.emptyActivity => _empty(),
        AndroidTemplate.basicViews => _basicViews(),
        AndroidTemplate.emptyCompose => _compose(),
        AndroidTemplate.bottomNavigation => _bottomNav(),
        AndroidTemplate.loginActivity => _login(),
        AndroidTemplate.scrollingActivity => _scrolling(),
        AndroidTemplate.navigationDrawer => _navDrawer(),
      };

  Widget _empty() => Container(
      color: const Color(0xFFF5F5F5),
      child: Center(child: _previewBar()));

  Widget _basicViews() => Column(children: [
        _previewAppBar(),
        Expanded(
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: Stack(children: [
              Center(child: _previewBar()),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                      color: Color(0xFFFB8C00),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 4,
                            offset: Offset(0, 2))
                      ]),
                  child:
                      const Icon(Icons.add, size: 13, color: Colors.white),
                ),
              ),
            ]),
          ),
        ),
      ]);

  Widget _compose() => Container(
      decoration: const BoxDecoration(
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6750A4), Color(0xFF7C4DFF)])),
      child: Center(
        child:
            Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.4),
                    width: 1.5)),
            child: const Icon(Icons.widgets_rounded,
                size: 16, color: Colors.white),
          ),
          const SizedBox(height: 8),
          _previewBar(
              width: 54, color: Colors.white.withValues(alpha: 0.75)),
          const SizedBox(height: 4),
          _previewBar(
              width: 36, color: Colors.white.withValues(alpha: 0.4)),
        ]),
      ));

  Widget _bottomNav() => Column(children: [
        Expanded(
            child: Container(
                color: const Color(0xFFF5F5F5),
                child: Center(child: _previewBar()))),
        _previewBottomNavBar(),
      ]);

  Widget _login() => Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.all(10),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        _previewBar(
            width: 40, height: 9, color: const Color(0xFF424242)),
        const SizedBox(height: 10),
        Container(
            height: 18,
            decoration: BoxDecoration(
                border:
                    Border.all(color: const Color(0xFF9E9E9E)),
                borderRadius: BorderRadius.circular(4),
                color: Colors.white)),
        const SizedBox(height: 6),
        Container(
            height: 18,
            decoration: BoxDecoration(
                border:
                    Border.all(color: const Color(0xFF9E9E9E)),
                borderRadius: BorderRadius.circular(4),
                color: Colors.white)),
        const SizedBox(height: 10),
        Container(
          height: 20,
          decoration: BoxDecoration(
              color: const Color(0xFF1565C0),
              borderRadius: BorderRadius.circular(4)),
          child: Center(
              child: _previewBar(
                  width: 36, height: 5, color: Colors.white)),
        ),
      ]));

  Widget _scrolling() => Column(children: [
        Container(
          height: 48,
          color: const Color(0xFF1565C0),
          alignment: Alignment.bottomLeft,
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          child: _previewBar(
              width: 52, color: Colors.white.withValues(alpha: 0.8)),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFFF5F5F5),
            padding: const EdgeInsets.all(8),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _previewBar(width: 80, height: 5),
                  const SizedBox(height: 4),
                  _previewBar(width: 60, height: 5),
                  const SizedBox(height: 4),
                  _previewBar(width: 70, height: 5),
                ]),
          ),
        ),
      ]);

  Widget _navDrawer() => Row(children: [
        Container(
          width: 50,
          color: const Color(0xFFFAFAFA),
          padding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    height: 20,
                    color: const Color(0xFF1565C0)
                        .withValues(alpha: 0.15),
                    margin: const EdgeInsets.only(bottom: 6)),
                ...List.generate(
                    3,
                    (_) => Container(
                        height: 12,
                        margin: const EdgeInsets.only(bottom: 4),
                        color: const Color(0xFFBDBDBD))),
              ]),
        ),
        Expanded(
          child: Column(children: [
            _previewAppBar(),
            Expanded(
                child: Container(
                    color: const Color(0xFFF5F5F5),
                    child: Center(child: _previewBar()))),
          ]),
        ),
      ]);
}

// ── Flutter previews ──────────────────────────────────────────────────────────

class _FlutterTemplatePreview extends StatelessWidget {
  final FlutterTemplate template;
  const _FlutterTemplatePreview({required this.template});

  @override
  Widget build(BuildContext context) => switch (template) {
        FlutterTemplate.counterApp => _counter(),
        FlutterTemplate.emptyApp => _empty(),
        FlutterTemplate.materialApp => _material(),
        FlutterTemplate.bottomNavApp => _bottomNav(),
        FlutterTemplate.drawerApp => _drawer(),
        FlutterTemplate.loginScreen => _login(),
        FlutterTemplate.listApp => _listView(),
        FlutterTemplate.tabsApp => _tabs(),
      };

  Widget _counter() => Column(children: [
        _previewAppBar(color: const Color(0xFF1565C0)),
        Expanded(
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: Stack(children: [
              Center(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    _previewBar(width: 40, height: 5),
                    const SizedBox(height: 6),
                    Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFF1565C0),
                                width: 2)),
                        child: Center(
                            child: _previewBar(
                                width: 14,
                                height: 5,
                                color: const Color(0xFF1565C0)))),
                  ])),
              Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                          color: Color(0xFF1565C0),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.add,
                          size: 13, color: Colors.white))),
            ]),
          ),
        ),
      ]);

  Widget _empty() => Container(
      color: const Color(0xFFF5F5F5),
      child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            const Icon(Icons.flutter_dash,
                size: 28, color: Color(0xFF54C5F8)),
            const SizedBox(height: 6),
            _previewBar(width: 48),
          ])));

  Widget _material() => Column(children: [
        _previewAppBar(color: const Color(0xFF6750A4)),
        Expanded(
          child: Container(
            color: const Color(0xFFF3F0FA),
            padding: const EdgeInsets.all(8),
            child: Column(children: [
              Container(
                  height: 22,
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 3)
                      ]),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: const Color(0xFF6750A4),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    _previewBar(width: 40, height: 5),
                  ])),
              Container(
                  height: 22,
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 3)
                      ]),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: const Color(0xFF7D5260),
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    _previewBar(width: 36, height: 5),
                  ])),
            ]),
          ),
        ),
      ]);

  Widget _bottomNav() => Column(children: [
        _previewAppBar(color: const Color(0xFF6750A4)),
        Expanded(
            child: Container(
                color: const Color(0xFFF5F5F5),
                child: Center(child: _previewBar()))),
        _previewBottomNavBar(active: const Color(0xFF6750A4)),
      ]);

  Widget _drawer() => Row(children: [
        Container(
          width: 44,
          color: const Color(0xFFF7F5FF),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                    height: 28,
                    color: const Color(0xFF3F2C91)
                        .withValues(alpha: 0.12)),
                const SizedBox(height: 6),
                ...List.generate(
                    3,
                    (i) => Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: Container(
                            height: 10,
                            decoration: BoxDecoration(
                              color: i == 0
                                  ? const Color(0xFF3F2C91)
                                      .withValues(alpha: 0.3)
                                  : const Color(0xFFBDBDBD),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        )),
              ]),
        ),
        Expanded(
            child: Column(children: [
          _previewAppBar(color: const Color(0xFF3F2C91)),
          Expanded(
              child: Container(
                  color: const Color(0xFFF5F5F5),
                  child: Center(child: _previewBar()))),
        ])),
      ]);

  Widget _login() => Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF6750A4).withValues(alpha: 0.15),
          ),
          child: const Icon(Icons.lock_rounded,
              size: 15, color: Color(0xFF6750A4)),
        ),
        const SizedBox(height: 6),
        _previewBar(
            width: 34, height: 5, color: const Color(0xFF424242)),
        const SizedBox(height: 8),
        Container(
            height: 14,
            decoration: BoxDecoration(
                border:
                    Border.all(color: const Color(0xFFBDBDBD)),
                borderRadius: BorderRadius.circular(4),
                color: Colors.white)),
        const SizedBox(height: 5),
        Container(
            height: 14,
            decoration: BoxDecoration(
                border:
                    Border.all(color: const Color(0xFFBDBDBD)),
                borderRadius: BorderRadius.circular(4),
                color: Colors.white)),
        const SizedBox(height: 8),
        Container(
          height: 18,
          decoration: BoxDecoration(
              color: const Color(0xFF6750A4),
              borderRadius: BorderRadius.circular(4)),
          child: Center(
              child: _previewBar(
                  width: 28, height: 5, color: Colors.white)),
        ),
      ]));

  Widget _listView() => Column(children: [
        _previewAppBar(color: const Color(0xFF00796B)),
        Expanded(
            child: Container(
          color: Colors.white,
          child: Column(children: [
            ...List.generate(
                3,
                (i) => Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        child: Row(children: [
                          Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: const Color(0xFF00796B)
                                      .withValues(alpha: 0.25),
                                  shape: BoxShape.circle)),
                          const SizedBox(width: 7),
                          Column(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                _previewBar(width: 50, height: 5),
                                const SizedBox(height: 3),
                                _previewBar(width: 36, height: 4),
                              ]),
                        ]),
                      ),
                      if (i < 2)
                        Container(
                            height: 1,
                            color: const Color(0xFFEEEEEE)),
                    ])),
          ]),
        )),
      ]);

  Widget _tabs() => Column(children: [
        Container(
          color: const Color(0xFF1565C0),
          child: Column(children: [
            SizedBox(
                height: 24,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: _previewBar(
                            width: 46,
                            height: 5,
                            color: Colors.white
                                .withValues(alpha: 0.55))))),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(
                  3,
                  (i) => Column(children: [
                        SizedBox(
                            height: 16,
                            child: Center(
                                child: _previewBar(
                                    width: 20,
                                    height: 4,
                                    color: i == 0
                                        ? Colors.white
                                        : Colors.white
                                            .withValues(alpha: 0.4)))),
                        Container(
                            height: 2,
                            width: 30,
                            color: i == 0
                                ? Colors.white
                                : Colors.transparent),
                      ])),
            ),
          ]),
        ),
        Expanded(
            child: Container(
                color: const Color(0xFFF5F5F5),
                child: Center(child: _previewBar()))),
      ]);
}

// ── React Native previews ─────────────────────────────────────────────────────

class _RnTemplatePreview extends StatelessWidget {
  final ReactNativeTemplate template;
  const _RnTemplatePreview({required this.template});

  @override
  Widget build(BuildContext context) => switch (template) {
        ReactNativeTemplate.blank => _blank(),
        ReactNativeTemplate.blankTypescript => _blankTs(),
        ReactNativeTemplate.tabs => _tabs(),
        ReactNativeTemplate.flatList => _flatList(),
        ReactNativeTemplate.settings => _settings(),
        ReactNativeTemplate.login => _login(),
      };

  Widget _blank() => Container(
      color: const Color(0xFF1C1E21),
      child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                    color: const Color(0xFF61DAFB)
                        .withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFF61DAFB), width: 1.5)),
                child: const Icon(Icons.code,
                    size: 13, color: Color(0xFF61DAFB))),
            const SizedBox(height: 8),
            _previewBar(
                width: 46,
                color: Colors.white.withValues(alpha: 0.7)),
          ])));

  Widget _blankTs() => Container(
      color: const Color(0xFF1C1E21),
      child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            Container(
                width: 30,
                height: 22,
                decoration: BoxDecoration(
                    color: const Color(0xFF3178C6),
                    borderRadius: BorderRadius.circular(4)),
                child: Center(
                    child: Text('TS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)))),
            const SizedBox(height: 8),
            _previewBar(
                width: 46,
                color: Colors.white.withValues(alpha: 0.7)),
          ])));

  Widget _tabs() => Column(children: [
        Container(height: 14, color: const Color(0xFF1C1E21)),
        Expanded(
            child: Container(
                color: const Color(0xFF1C1E21),
                child: Center(
                    child: _previewBar(
                        width: 48,
                        color:
                            Colors.white.withValues(alpha: 0.7))))),
        Container(
          height: 36,
          decoration: BoxDecoration(
              color: const Color(0xFF2C2E33),
              boxShadow: const [
                BoxShadow(
                    color: Colors.black45,
                    blurRadius: 8,
                    offset: Offset(0, -2))
              ]),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(3, (i) {
                final active = i == 0;
                return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                          width: 18,
                          height: 10,
                          decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF61DAFB)
                                  : const Color(0xFF555555),
                              borderRadius:
                                  BorderRadius.circular(3))),
                      const SizedBox(height: 2),
                      Container(
                          width: 22,
                          height: 4,
                          decoration: BoxDecoration(
                              color: active
                                  ? const Color(0xFF61DAFB)
                                  : const Color(0xFF555555),
                              borderRadius:
                                  BorderRadius.circular(2))),
                    ]);
              })),
        ),
      ]);

  Widget _flatList() => Column(children: [
        Container(
          height: 24,
          color: const Color(0xFF2196F3),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.centerLeft,
          child: _previewBar(
              width: 38,
              height: 5,
              color: Colors.white.withValues(alpha: 0.85)),
        ),
        Expanded(
            child: Container(
          color: const Color(0xFF252628),
          child: Column(children: [
            ...List.generate(
                3,
                (i) => Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 7),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _previewBar(
                                  width: 56,
                                  height: 5,
                                  color: Colors.white
                                      .withValues(alpha: 0.8)),
                              const SizedBox(height: 3),
                              _previewBar(
                                  width: 40,
                                  height: 4,
                                  color: Colors.white
                                      .withValues(alpha: 0.4)),
                            ]),
                      ),
                      if (i < 2)
                        Container(
                            height: 1,
                            color:
                                Colors.white.withValues(alpha: 0.07)),
                    ])),
          ]),
        )),
      ]);

  Widget _settings() => Container(
      color: const Color(0xFF1C1E21),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
          child: _previewBar(
              width: 38,
              height: 4,
              color: Colors.white.withValues(alpha: 0.35)),
        ),
        Container(
          color: const Color(0xFF2C2E33),
          child: Column(children: [
            ...List.generate(
                2,
                (i) => Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 10),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            _previewBar(
                                width: 48,
                                height: 5,
                                color: Colors.white
                                    .withValues(alpha: 0.75)),
                            Container(
                              width: 24,
                              height: 13,
                              decoration: BoxDecoration(
                                color: i == 0
                                    ? const Color(0xFF61DAFB)
                                        .withValues(alpha: 0.85)
                                    : const Color(0xFF555555),
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < 1)
                        Container(
                            height: 1,
                            color: Colors.white
                                .withValues(alpha: 0.07)),
                    ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
          child: _previewBar(
              width: 32,
              height: 4,
              color: Colors.white.withValues(alpha: 0.35)),
        ),
        Container(
          color: const Color(0xFF2C2E33),
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: _previewBar(
              width: 48,
              height: 5,
              color: Colors.white.withValues(alpha: 0.75)),
        ),
      ]));

  Widget _login() => Container(
      color: const Color(0xFF1C1E21),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF2196F3).withValues(alpha: 0.18),
            border:
                Border.all(color: const Color(0xFF2196F3), width: 1.5),
          ),
          child: const Icon(Icons.lock_outline,
              size: 13, color: Color(0xFF2196F3)),
        ),
        const SizedBox(height: 7),
        _previewBar(
            width: 32,
            height: 5,
            color: Colors.white.withValues(alpha: 0.8)),
        const SizedBox(height: 9),
        Container(
          height: 15,
          decoration: BoxDecoration(
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFF2C2E33),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 15,
          decoration: BoxDecoration(
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.18)),
            borderRadius: BorderRadius.circular(4),
            color: const Color(0xFF2C2E33),
          ),
        ),
        const SizedBox(height: 9),
        Container(
          height: 18,
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Center(
              child: _previewBar(
                  width: 28, height: 5, color: Colors.white)),
        ),
      ]));
}

// ── SDK detecting tile ────────────────────────────────────────────────────────

class _SdkDetectingTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outline),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: cs.primary),
          ),
          const SizedBox(width: 12),
          Text(
            'Detecting SDKs on remote machine…',
            style: GoogleFonts.openSans(
                color: cs.onSurfaceVariant, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ── No SDK warning ────────────────────────────────────────────────────────────

class _NoSdkWarning extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: cs.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppStrings.of(context).noSdkInstalled,
              style: GoogleFonts.openSans(
                  color: cs.onErrorContainer, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}