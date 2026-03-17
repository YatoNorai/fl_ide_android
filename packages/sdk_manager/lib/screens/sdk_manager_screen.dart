import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../models/sdk_definition.dart';
import '../providers/sdk_manager_provider.dart';

class SdkManagerScreen extends StatelessWidget {
  const SdkManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBg,
      appBar: AppBar(
        backgroundColor: AppTheme.darkBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.darkText),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('SDK Manager',
            style: TextStyle(
                color: AppTheme.darkText,
                fontSize: 20,
                fontWeight: FontWeight.w600)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.darkText, size: 22),
            onPressed: () => context.read<SdkManagerProvider>().checkAll(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<SdkManagerProvider>(
        builder: (context, sdk, _) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: SdkDefinition.all.length,
          separatorBuilder: (_, __) =>
              const Divider(color: AppTheme.darkDivider, height: 1),
          itemBuilder: (context, i) {
            final def = SdkDefinition.all[i];
            return _SdkTile(def: def, sdk: sdk);
          },
        ),
      ),
    );
  }
}

class _SdkTile extends StatelessWidget {
  final SdkDefinition def;
  final SdkManagerProvider sdk;

  const _SdkTile({required this.def, required this.sdk});

  @override
  Widget build(BuildContext context) {
    final installed = sdk.isInstalled(def.type);
    final loading = sdk.isLoading(def.type);
    final version = sdk.version(def.type);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(def.type.icon, style: const TextStyle(fontSize: 24)),
        ),
      ),
      title: Text(def.type.displayName,
          style: const TextStyle(
              color: AppTheme.darkText,
              fontSize: 16,
              fontWeight: FontWeight.w500)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(def.type.description,
              style: const TextStyle(
                  color: AppTheme.darkTextMuted, fontSize: 13)),
          if (installed && version != null) ...[
            const SizedBox(height: 2),
            Text('v$version',
                style: const TextStyle(
                    color: AppTheme.darkSuccess, fontSize: 12)),
          ],
        ],
      ),
      trailing: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: AppTheme.darkAccent),
            )
          : installed
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: AppTheme.darkSuccess, size: 20),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _openInstall(context, def),
                      child: const Text('Update',
                          style: TextStyle(
                              color: AppTheme.darkAccent, fontSize: 12)),
                    ),
                  ],
                )
              : ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.darkAccent,
                    foregroundColor: const Color(0xFF001849),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    elevation: 0,
                  ),
                  onPressed: () => _openInstall(context, def),
                  child: const Text('Install'),
                ),
    );
  }

  void _openInstall(BuildContext context, SdkDefinition def) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _InstallSheet(def: def),
    );
  }
}

class _InstallSheet extends StatefulWidget {
  final SdkDefinition def;
  const _InstallSheet({required this.def});

  @override
  State<_InstallSheet> createState() => _InstallSheetState();
}

class _InstallSheetState extends State<_InstallSheet> {
  late TerminalProvider _termProvider;

  @override
  void initState() {
    super.initState();
    _termProvider = TerminalProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = await _termProvider.createSession(
        label: 'Installing ${widget.def.type.displayName}',
      );
      session.writeCommand(widget.def.installScript);
    });
  }

  @override
  void dispose() {
    _termProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(widget.def.type.icon,
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Installing ${widget.def.type.displayName}',
                    style: const TextStyle(
                        color: AppTheme.darkText,
                        fontSize: 16,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    context
                        .read<SdkManagerProvider>()
                        .markInstalled(widget.def.type);
                    Navigator.pop(context);
                  },
                  child: const Text('Done',
                      style: TextStyle(
                          color: AppTheme.darkAccent,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          const Divider(color: AppTheme.darkDivider),
          Expanded(
            child: ChangeNotifierProvider.value(
              value: _termProvider,
              child: const TerminalTabs(),
            ),
          ),
        ],
      ),
    );
  }
}
