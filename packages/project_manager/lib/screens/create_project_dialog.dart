import 'dart:io';

import 'package:core/core.dart';
import 'package:fl_ide/l10n/app_strings.dart';
import 'package:fl_ide/providers/extensions_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/project_manager_provider.dart';

/// Full-screen project creation form.
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});

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

  // SDKs that use a package/bundle identifier
  static const _pkgSdks = {SdkType.flutter, SdkType.androidSdk, SdkType.reactNative};

  bool get _supportsPackage =>
      _selectedSdk != null && _pkgSdks.contains(_selectedSdk);

  bool get _canCreate =>
      !_creating &&
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
  String _nextAvailableName() {
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
    _termProvider.dispose();
    super.dispose();
  }

  Future<void> _pickSdk() async {
    final sdkMgr = context.read<SdkManagerProvider>();
    final installed = sdkMgr.installedSdks;
    if (installed.isEmpty) return;

    final result = await showDialog<SdkType>(
      context: context,
      builder: (ctx) => _SdkPickerDialog(
        options: installed,
        selected: _selectedSdk,
      ),
    );
    if (result != null) setState(() => _selectedSdk = result);
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedSdk == null) return;
    setState(() => _creating = true);

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
      runInTerminal: (script) async {
        await _termProvider.createSession(label: 'Criando $name');
        _termProvider.active?.writeCommand(script);
      },
    );

    if (!mounted) return;
    pm.openProject(project, isNew: true);
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    final sdkMgr = context.watch<SdkManagerProvider>();
    final noSdks = sdkMgr.installedSdks.isEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'FL IDE',
          style: TextStyle(
            color: cs.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
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
              style: TextStyle(
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
                  // SDK selector tile
                  if (noSdks)
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
                    style: TextStyle(color: cs.onSurface, fontSize: 15),
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
                      style: TextStyle(color: cs.onSurface, fontSize: 15),
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

                  // Terminal output while creating
                  if (_creating) ...[
                    const SizedBox(height: 20),
                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ChangeNotifierProvider.value(
                          value: _termProvider,
                          child: const TerminalTabs(),
                        ),
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
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _creating ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(s.cancel),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton(
                      onPressed: _canCreate ? _create : null,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                          _creating ? s.creating : s.createProject),
                    ),
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
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    selected == null
                        ? AppStrings.of(context).selectSdk
                        : '${selected!.icon}  ${selected!.displayName}',
                    style: TextStyle(
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
                style: const TextStyle(fontSize: 22)),
            title: Text(sdk.displayName),
            subtitle: Text(sdk.description,
                style: TextStyle(
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
              style: TextStyle(color: cs.onErrorContainer, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
