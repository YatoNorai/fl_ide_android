import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:core/core.dart';
import 'package:fl_ide/l10n/app_strings.dart';
import 'package:fl_ide/providers/extensions_provider.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/project_manager_provider.dart';

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

  // SDKs that use a package/bundle identifier
  static const _pkgSdks = {SdkType.flutter, SdkType.androidSdk, SdkType.reactNative};

  /// Map a human-readable SDK name (from SSH detection) to SdkType.
  static SdkType? _sdkTypeFromName(String name) {
    switch (name) {
      case 'Flutter':     return SdkType.flutter;
      case 'Android SDK': return SdkType.androidSdk;
      case 'Node.js':     return SdkType.nodejs;
      case 'Python':      return SdkType.python;
      default:            return null;
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

  /// Returns 'application', 'application_1', 'application_2', … whichever
  /// is the first name whose folder does not yet exist in the projects dir.
  /// For remote projects, skips local FS check.
  String _nextAvailableName() {
    if (widget.remoteProjectsPath != null) return 'application';
    final base = 'application';
    final dir = RuntimeEnvir.projectsPath;
    if (!Directory('$dir/$base').existsSync()) return base;
    for (int i = 1; ; i++) {
      final candidate = '${base}_$i';
      if (!Directory('$dir/$candidate').existsSync()) return candidate;
    }
  }

  void _syncPackage() {
    final safe = _nameCtrl.text.trim().toLowerCase()
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
    // Complete the creation completer so the awaiting callback doesn't hang
    // if the screen is dismissed early (e.g. Android back button).
    _createDone?.complete();
    _termProvider.dispose();
    super.dispose();
  }

  Future<void> _pickSdk() async {
    // When SSH is active, show the SDKs detected on the remote machine.
    // Fall back to locally installed SDKs.
    final options = widget.isSshActive && _remoteSdkTypes.isNotEmpty
        ? _remoteSdkTypes
        : context.read<SdkManagerProvider>().installedSdks;
    if (options.isEmpty) return;

    final result = await showThemedDialog<SdkType>(
      context: context,
      builder: (ctx) => _SdkPickerDialog(
        options: options,
        selected: _selectedSdk,
      ),
    );
    if (result != null) setState(() => _selectedSdk = result);
  }

  void _showProgressDialog(String name) {
    _progressNotifier = ValueNotifier(0.0);
    // Animate: exponential approach toward 85% while work runs in background.
    _progressTimer = Timer.periodic(const Duration(milliseconds: 150), (_) {
      if (_progressNotifier == null) return;
      final remaining = 0.85 - _progressNotifier!.value;
      _progressNotifier!.value += remaining * 0.045;
    });
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      pageBuilder: (_, __, ___) => _CreatingProgressDialog(
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

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedSdk == null) return;
    setState(() => _creating = true);
    _showProgressDialog(name);

    // Prefer the installed JSON extension's newProjectCmd if available.
    final extProv = context.read<ExtensionsProvider>();
    final ext = extProv.availableSdks
        .where((e) => e.sdk == _selectedSdk!.name)
        .firstOrNull;
    final overrideCmd = ext?.sdkConfig?.newProjectCmd;

    final pm = context.read<ProjectManagerProvider>();
    final project = await pm.createProject(
      name: name,
      sdk: _selectedSdk!,
      newProjectCmd: overrideCmd,
      projectsBasePath: widget.remoteProjectsPath,
      remoteIsWindows: widget.remoteIsWindows,
      runInTerminal: (script) async {
        await _termProvider.createSession(
          label: 'Criando $name',
          sshSetup: widget.sshTerminalSetup,
        );
        final session = _termProvider.active;
        if (session == null) return;

        if (widget.sshTerminalSetup != null) {
          // Set up exit listener BEFORE writing the command to avoid a race
          // where the shell exits before the listener is registered.
          _createDone = Completer<void>();
          final prev = session.onExit;
          session.onExit = (code) {
            prev?.call(code);
            if (!_createDone!.isCompleted) _createDone!.complete();
          };

          // Append exit so the shell closes when the create command finishes,
          // letting onExit fire to signal completion.
          // Both PowerShell (Windows SSH default) and POSIX shells use ';'.
          session.writeCommand('$script; exit');

          // Wait for the shell to exit (= create command completed).
          await _createDone!.future;
          _createDone = null;
        } else {
          // Local: just write the command; terminal stays open for user to see output.
          session.writeCommand(script);
        }
      },
    );

    await _closeProgressDialog();
    if (!mounted) return;
    pm.openProject(project, isNew: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    final sdkMgr = context.watch<SdkManagerProvider>();
    final detecting = widget.isSshActive && widget.isSshDetecting;
    final noSdks = !detecting && (widget.isSshActive
        ? _remoteSdkTypes.isEmpty
        : sdkMgr.installedSdks.isEmpty);

    return Scaffold(
    //  backgroundColor: cs.surface,
      appBar: AppBar(
      ///  backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title:  Text(
  "L A Y E R",
  style: GoogleFonts.montserrat( // Ou .inter, .poppins, etc.
    fontSize: 18,
    fontWeight: FontWeight.w400,
    letterSpacing: 5.0,
  //  color: Colors.white.withOpacity(0.9),
  ),
),
        centerTitle: true,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ───────────────────────────────────────────────────────
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

          // ── Scrollable fields ────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SSH indicator banner
                  if (widget.isSshActive && widget.remoteProjectsPath != null) ...[
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

                  // SDK selector tile
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

                  // Project name field
                  TextField(
                    controller: _nameCtrl,
                    enabled: !_creating,
                    style: GoogleFonts.openSans(color: cs.onSurface, fontSize: 15),
                    decoration: InputDecoration(
                      labelText: s.projectName,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide:
                            BorderSide(color: cs.primary, width: 2),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.outlineVariant),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),

                  // Package name (Flutter / Android / React Native only)
                  if (_supportsPackage) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _packageCtrl,
                      enabled: !_creating,
                      style: GoogleFonts.openSans(color: cs.onSurface, fontSize: 15),
                      decoration: InputDecoration(
                        labelText: s.packageName,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outline),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: cs.primary, width: 2),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: cs.outlineVariant),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Bottom buttons ───────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton(
                    onPressed:
                        _creating ? null : () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                  //    padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(s.cancel),
                  ),
                  
                  FilledButton(
                    onPressed: _canCreate ? _create : null,
                    style: FilledButton.styleFrom(
                     // padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                    ),
                    child: Text(
                        _creating ? s.creating : s.createProject),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
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
            Icon(Icons.arrow_drop_down_rounded,
                color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

// ── SDK picker dialog ─────────────────────────────────────────────────────────

class _SdkPickerDialog extends StatelessWidget {
  final List<SdkType> options;
  final SdkType? selected;

  const _SdkPickerDialog({required this.options, required this.selected});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(AppStrings.of(context).selectSdk),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((sdk) {
          final isSelected = sdk == selected;
          return ListTile(
            leading: Text(sdk.icon,
                style:  GoogleFonts.openSans(fontSize: 22)),
            title: Text(sdk.displayName),
            subtitle: Text(sdk.description,
                style: GoogleFonts.openSans(
                    color: cs.onSurfaceVariant, fontSize: 12)),
            trailing: isSelected
                ? Icon(Icons.check_rounded, color: cs.primary)
                : null,
            selected: isSelected,
            onTap: () => Navigator.pop(context, sdk),
          );
        }).toList(),
      ),
    );
  }
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
              strokeWidth: 2,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Detecting SDKs on remote machine…',
            style: GoogleFonts.openSans(color: cs.onSurfaceVariant, fontSize: 14),
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
              style: GoogleFonts.openSans(color: cs.onErrorContainer, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Creating progress dialog ──────────────────────────────────────────────────

class _CreatingProgressDialog extends StatelessWidget {
  final String projectName;
  final ValueNotifier<double> progressNotifier;

  const _CreatingProgressDialog({
    required this.projectName,
    required this.progressNotifier,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(color: Colors.black.withValues(alpha: 0.35)),
          ),
          Center(
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                title: Row(
                  children: [
                    Icon(Icons.folder_open_rounded, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    const Text('Criando projeto'),
                  ],
                ),
                content: ValueListenableBuilder<double>(
                  valueListenable: progressNotifier,
                  builder: (_, progress, __) {
                    final pct = (progress * 100).clamp(0, 100).round();
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          projectName,
                          style: GoogleFonts.openSans(
                            color: cs.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
