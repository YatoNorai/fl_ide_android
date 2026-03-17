import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/extension_theme_meta.dart';
import '../providers/extensions_provider.dart';

class ExtensionsScreen extends StatefulWidget {
  const ExtensionsScreen({super.key});

  @override
  State<ExtensionsScreen> createState() => _ExtensionsScreenState();
}

class _ExtensionsScreenState extends State<ExtensionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ExtensionsProvider(),
      child: _ExtensionsBody(tabController: _tab),
    );
  }
}

class _ExtensionsBody extends StatelessWidget {
  final TabController tabController;
  const _ExtensionsBody({required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Extensions'),
        bottom: TabBar(
          controller: tabController,
          tabs: const [
            Tab(icon: Icon(Icons.store_outlined), text: 'Store'),
            Tab(icon: Icon(Icons.download_done_outlined), text: 'Installed'),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: const [
          _StoreTab(),
          _InstalledTab(),
        ],
      ),
    );
  }
}

// ── Store tab ──────────────────────────────────────────────────────────────

class _StoreTab extends StatelessWidget {
  const _StoreTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        if (prov.loadingIndex && prov.availableThemes.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (prov.indexError != null && prov.availableThemes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.wifi_off_outlined, size: 48),
                const SizedBox(height: 12),
                Text(prov.indexError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: prov.fetchIndex,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        if (prov.availableThemes.isEmpty) {
          return const Center(child: Text('No themes available.'));
        }

        // Split by dark/light
        final dark = prov.availableThemes.where((t) => t.dark).toList();
        final light = prov.availableThemes.where((t) => !t.dark).toList();

        return RefreshIndicator(
          onRefresh: prov.fetchIndex,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              _sectionLabel(context, '🌙 Dark Themes'),
              ...dark.map((t) => _ThemeStoreCard(meta: t)),
              const SizedBox(height: 8),
              _sectionLabel(context, '☀️ Light Themes'),
              ...light.map((t) => _ThemeStoreCard(meta: t)),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _ThemeStoreCard extends StatelessWidget {
  final ExtensionThemeMeta meta;
  const _ThemeStoreCard({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        final installed = prov.isInstalled(meta.id);
        final downloading = prov.isDownloading(meta.id);
        final active = prov.isActive(meta.id);
        final colors = Theme.of(context).colorScheme;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _ColorSwatch(hexColor: meta.preview, dark: meta.dark),
            title: Row(
              children: [
                Text(meta.name,
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                if (active) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text('Active',
                        style: TextStyle(
                            fontSize: 10, color: colors.onPrimaryContainer)),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              meta.dark ? 'Dark theme' : 'Light theme',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: downloading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : installed
                    ? IconButton(
                        icon: Icon(Icons.check_circle,
                            color: colors.primary),
                        tooltip: 'Installed',
                        onPressed: () => _showInstalledOptions(
                            context, prov, meta, active),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Download',
                        onPressed: () => _confirmDownload(context, prov, meta),
                      ),
          ),
        );
      },
    );
  }

  void _confirmDownload(BuildContext context, ExtensionsProvider prov,
      ExtensionThemeMeta meta) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Download "${meta.name}"?'),
        content: Text(
          'This will download the theme JSON (~2 KB) from GitHub and '
          'save it to your device.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              prov.downloadTheme(meta).then((_) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('"${meta.name}" downloaded!'),
                      behavior: SnackBarBehavior.floating));
                }
              });
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  void _showInstalledOptions(BuildContext context, ExtensionsProvider prov,
      ExtensionThemeMeta meta, bool active) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: Icon(
              active ? Icons.radio_button_checked : Icons.radio_button_off,
              color: active
                  ? Theme.of(ctx).colorScheme.primary
                  : null,
            ),
            title: Text(active ? 'Deactivate theme' : 'Activate theme'),
            onTap: () {
              Navigator.pop(ctx);
              if (active) {
                prov.deactivateTheme();
              } else {
                prov.activateTheme(meta.id);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(ctx);
              prov.deleteTheme(meta.id);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Installed tab ──────────────────────────────────────────────────────────

class _InstalledTab extends StatelessWidget {
  const _InstalledTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        if (prov.installedThemes.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.extension_outlined, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('No extensions installed yet.',
                    style: TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                const Text('Go to Store to download themes.',
                    style: TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
          );
        }

        final active = prov.activeMeta;

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            if (active != null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  '✅ Active Theme',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              _InstalledThemeCard(meta: active),
              const SizedBox(height: 8),
              const Divider(),
            ],
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Installed',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            ...prov.installedThemes
                .where((t) => t.id != prov.activeThemeId)
                .map((t) => _InstalledThemeCard(meta: t)),
            const SizedBox(height: 24),
          ],
        );
      },
    );
  }
}

class _InstalledThemeCard extends StatelessWidget {
  final ExtensionThemeMeta meta;
  const _InstalledThemeCard({required this.meta});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        final active = prov.isActive(meta.id);
        final colors = Theme.of(context).colorScheme;

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          color: active
              ? colors.primaryContainer.withValues(alpha: 0.3)
              : null,
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: _ColorSwatch(hexColor: meta.preview, dark: meta.dark),
            title: Text(meta.name,
                style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(
              meta.dark ? 'Dark theme' : 'Light theme',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Toggle active
                Switch(
                  value: active,
                  onChanged: (val) {
                    if (val) {
                      prov.activateTheme(meta.id);
                    } else {
                      prov.deactivateTheme();
                    }
                  },
                ),
                // Delete
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red,
                      size: 20),
                  tooltip: 'Delete',
                  onPressed: () => _confirmDelete(context, prov, meta),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, ExtensionsProvider prov,
      ExtensionThemeMeta meta) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${meta.name}"?'),
        content: const Text('The theme file will be removed from your device.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              prov.deleteTheme(meta.id);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────

class _ColorSwatch extends StatelessWidget {
  final String hexColor;
  final bool dark;
  const _ColorSwatch({required this.hexColor, required this.dark});

  @override
  Widget build(BuildContext context) {
    final s = hexColor.replaceFirst('#', '');
    final argb = s.length == 6 ? 'FF$s' : s;
    final color = Color(int.tryParse(argb, radix: 16) ?? 0xFF1E1E2E);

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
        ),
      ),
      child: Center(
        child: Icon(
          dark ? Icons.nightlight_round : Icons.wb_sunny_outlined,
          size: 18,
          color: dark ? Colors.white70 : Colors.black54,
        ),
      ),
    );
  }
}
