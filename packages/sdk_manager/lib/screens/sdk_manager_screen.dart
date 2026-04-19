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
        builder: (context, sdk, _) => ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: SdkDefinition.all.length,
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

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openInstall(context, def),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: installed
                  ? cs.primary.withValues(alpha: 0.25)
                  : cs.outline.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row: icon + name + status indicator ──
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text(def.type.icon,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(def.type.displayName,
                              style: TextStyle(
                                  color: cs.onSurface,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          if (installed && version != null)
                            Text('v$version',
                                style: TextStyle(
                                    color: cs.primary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    if (loading)
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.5, color: cs.primary),
                      )
                    else if (installed)
                      Icon(Icons.check_circle_rounded,
                          color: cs.primary, size: 20),
                  ],
                ),
                // ── Description ──
                const SizedBox(height: 8),
                Text(def.type.description,
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                        height: 1.4)),
                // ── Action buttons row ──
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (installed) ...[
                      OutlinedButton.icon(
                        onPressed: () => _openInstall(context, def),
                        icon: const Icon(Icons.update_rounded, size: 16),
                        label: const Text('Update'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ] else ...[
                      FilledButton.icon(
                        onPressed: loading
                            ? null
                            : () => _openInstall(context, def),
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('Install'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
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
      // Use the provider's installCommand so the cleanup trap is included.
      final cmd = SdkManagerProvider().installCommand(widget.def.type);
      session.writeCommand(cmd);
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
