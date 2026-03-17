import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/project_manager_provider.dart';

/// AndroidIDE-style full-screen project creation form.
/// Exported as [CreateProjectScreen] (full page) and [CreateProjectDialog] (kept for compat).
class CreateProjectScreen extends StatefulWidget {
  const CreateProjectScreen({super.key});

  @override
  State<CreateProjectScreen> createState() => _CreateProjectScreenState();
}

// Keep old name as alias so existing import in home_screen works
typedef CreateProjectDialog = CreateProjectScreen;

class _CreateProjectScreenState extends State<CreateProjectScreen> {
  final _nameCtrl = TextEditingController();
  SdkType? _selectedSdk;
  bool _creating = false;
  late final TerminalProvider _termProvider;

  @override
  void initState() {
    super.initState();
    _termProvider = TerminalProvider();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _termProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sdkMgr = context.watch<SdkManagerProvider>();
    final installedSdks = sdkMgr.installedSdks;

    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.darkText),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            const Center(
              child: Text('FL IDE',
                  style: TextStyle(
                      color: AppTheme.darkText,
                      fontSize: 22,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('New project',
                  style: TextStyle(
                      color: AppTheme.darkText,
                      fontSize: 28,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Project name field
                    TextField(
                      controller: _nameCtrl,
                      style: const TextStyle(color: AppTheme.darkText, fontSize: 16),
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Application name',
                        prefixIcon: Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.android_outlined,
                              color: AppTheme.darkText, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Save path
                    TextField(
                      enabled: false,
                      style: const TextStyle(
                          color: AppTheme.darkTextMuted, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Save location',
                        hintText: RuntimeEnvir.projectsPath,
                        prefixIcon: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Icon(Icons.folder_outlined,
                              color: AppTheme.darkTextMuted, size: 20),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppTheme.darkBorder),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // SDK selector
                    if (installedSdks.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.darkBorder),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                color: AppTheme.darkWarning, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'No SDKs installed. Install an SDK first.',
                                style: TextStyle(
                                    color: AppTheme.darkTextMuted, fontSize: 14),
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      _SdkDropdown(
                        label: 'Project SDK',
                        selected: _selectedSdk,
                        options: installedSdks,
                        onChanged: (v) => setState(() => _selectedSdk = v),
                      ),
                    ],

                    // Terminal during creation
                    if (_creating) ...[
                      const SizedBox(height: 20),
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppTheme.darkBorder),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ChangeNotifierProvider.value(
                            value: _termProvider,
                            child: const TerminalTabs(),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),

            // Bottom buttons — identical to AndroidIDE screenshot 3
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _creating ? null : () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _creating ||
                              _selectedSdk == null ||
                              _nameCtrl.text.trim().isEmpty
                          ? null
                          : _create,
                      child: Text(_creating ? 'Creating...' : 'Create project'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedSdk == null) return;

    setState(() => _creating = true);

    await context.read<ProjectManagerProvider>().createProject(
      name: name,
      sdk: _selectedSdk!,
      runInTerminal: (script) async {
        await _termProvider.createSession(label: 'Creating $name');
        _termProvider.active?.writeCommand(script);
      },
    );

    if (mounted) Navigator.pop(context);
  }
}

// ── SDK dropdown ──────────────────────────────────────────────────────────────

class _SdkDropdown extends StatelessWidget {
  final String label;
  final SdkType? selected;
  final List<SdkType> options;
  final ValueChanged<SdkType?> onChanged;

  const _SdkDropdown({
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.darkBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<SdkType>(
          value: selected,
          isExpanded: true,
          dropdownColor: AppTheme.darkSurface,
          hint: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppTheme.darkTextMuted, fontSize: 12)),
              const Text('Select SDK',
                  style: TextStyle(color: AppTheme.darkText, fontSize: 16)),
            ],
          ),
          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.darkTextMuted),
          items: options
              .map((t) => DropdownMenuItem(
                    value: t,
                    child: Row(
                      children: [
                        Text(t.icon, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(label,
                                style: const TextStyle(
                                    color: AppTheme.darkTextMuted,
                                    fontSize: 12)),
                            Text(t.displayName,
                                style: const TextStyle(
                                    color: AppTheme.darkText, fontSize: 16)),
                          ],
                        ),
                      ],
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          selectedItemBuilder: (context) => options
              .map((t) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(label,
                          style: const TextStyle(
                              color: AppTheme.darkTextMuted, fontSize: 12)),
                      Row(
                        children: [
                          Text(t.icon, style: const TextStyle(fontSize: 16)),
                          const SizedBox(width: 8),
                          Text(t.displayName,
                              style: const TextStyle(
                                  color: AppTheme.darkText, fontSize: 16)),
                        ],
                      ),
                    ],
                  ))
              .toList(),
        ),
      ),
    );
  }
}
