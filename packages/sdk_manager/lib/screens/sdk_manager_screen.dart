import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../models/sdk_definition.dart';
import '../providers/sdk_manager_provider.dart';

class SdkManagerScreen extends StatelessWidget {
  const SdkManagerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: cs.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('SDK Manager',
            style: TextStyle(
                color: cs.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh_rounded, color: cs.onSurface, size: 22),
            onPressed: () => context.read<SdkManagerProvider>().checkAll(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Consumer<SdkManagerProvider>(
        builder: (context, sdk, _) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: SdkDefinition.all.length,
          separatorBuilder: (_, __) => Divider(
              color: cs.outline.withValues(alpha: 0.12), height: 1, indent: 16),
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
    final cs = Theme.of(context).colorScheme;
    final installed = sdk.isInstalled(def.type);
    final loading = sdk.isLoading(def.type);
    final version = sdk.version(def.type);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Text(def.type.icon, style: const TextStyle(fontSize: 24)),
        ),
      ),
      title: Text(def.type.displayName,
          style: TextStyle(
              color: cs.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(def.type.description,
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontSize: 13)),
          if (installed && version != null) ...[
            const SizedBox(height: 2),
            Text('v$version',
                style: TextStyle(
                    color: cs.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ],
        ],
      ),
      trailing: loading
          ? SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                  strokeWidth: 2.5, color: cs.primary),
            )
          : installed
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: cs.primary, size: 20),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => _openInstall(context, def),
                      child: Text('Update',
                          style: TextStyle(
                              color: cs.primary, fontSize: 12)),
                    ),
                  ],
                )
              : FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 12),
              decoration: BoxDecoration(
                color: cs.outline.withValues(alpha: 0.3),
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
                    style: TextStyle(
                        color: cs.onSurface,
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
                  child: Text('Done',
                      style: TextStyle(
                          color: cs.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          Divider(color: cs.outline.withValues(alpha: 0.15)),
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
