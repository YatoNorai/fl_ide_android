import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';

import '../models/extension_theme_meta.dart';
import '../providers/extensions_provider.dart';

// ── Extensions page content ─────────────────────────────────────────────────
// Designed to live inside the Settings CustomScrollView (shrinkWrap).
// Uses a local tab index instead of TabBarView so it scrolls as one block.

class ExtensionsPageContent extends StatefulWidget {
  const ExtensionsPageContent({super.key});

  @override
  State<ExtensionsPageContent> createState() => _ExtensionsPageContentState();
}

class _ExtensionsPageContentState extends State<ExtensionsPageContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _tab.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Tab selector ────────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceTint.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(4),
          child: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            /* unselectedLabelColor: Colors.white, */
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            splashBorderRadius: BorderRadius.circular(20),
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.store_outlined, size: 18), text: 'Store'),
              Tab(icon: Icon(Icons.extension_outlined, size: 18), text: 'SDKs'),
              Tab(icon: Icon(Icons.download_done_outlined, size: 18), text: 'Installed'),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Content for selected tab ────────────────────────────────────────
        if (_tab.index == 0)
          const _StoreContent()
        else if (_tab.index == 1)
          const _SdkContent()
        else
          const _InstalledContent(),

        const SizedBox(height: 32),
      ],
    );
  }
}

// ── Store content ────────────────────────────────────────────────────────────

class _StoreContent extends StatelessWidget {
  const _StoreContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        if (prov.loadingIndex && prov.availableThemes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (prov.indexError != null && prov.availableThemes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40, color: Colors.grey),
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
            ),
          );
        }

        if (prov.availableThemes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No themes available.')),
          );
        }

        final dark = prov.availableThemes.where((t) => t.dark).toList();
        final light = prov.availableThemes.where((t) => !t.dark).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context, 'Dark Themes'),
            ..._group(context, prov, dark),
            const SizedBox(height: 8),
            _sectionLabel(context, 'Light Themes'),
            ..._group(context, prov, light),
          ],
        );
      },
    );
  }

  List<Widget> _group(BuildContext context, ExtensionsProvider prov,
      List<ExtensionThemeMeta> themes) {
    return themes.asMap().entries.map((e) {
      final i = e.key;
      final isFirst = i == 0;
      final isLast = i == themes.length - 1;
      return _ThemeCard(
        meta: e.value,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(30) : const Radius.circular(10),
          bottom:
              isLast ? const Radius.circular(30) : const Radius.circular(10),
        ),
      );
    }).toList();
  }
}

// ── Installed content ────────────────────────────────────────────────────────

class _InstalledContent extends StatelessWidget {
  const _InstalledContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        if (prov.installedThemes.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.extension_outlined, size: 40, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('No extensions installed yet.',
                      style: TextStyle(color: Colors.grey)),
                  SizedBox(height: 4),
                  Text('Go to Store to install themes.',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ),
          );
        }

        final activeMeta = prov.activeMeta;
        final inactive = prov.installedThemes
            .where((t) => t.id != prov.activeThemeId)
            .toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (activeMeta != null) ...[
              _sectionLabel(context, 'Active Theme'),
              _InstalledCard(
                meta: activeMeta,
                borderRadius: const BorderRadius.all(Radius.circular(30)),
              ),
              const SizedBox(height: 8),
              const Divider(),
            ],
            if (inactive.isNotEmpty) ...[
              _sectionLabel(context, 'Installed'),
              ...inactive.asMap().entries.map((e) {
                final i = e.key;
                final isFirst = i == 0;
                final isLast = i == inactive.length - 1;
                return _InstalledCard(
                  meta: e.value,
                  borderRadius: BorderRadius.vertical(
                    top: isFirst
                        ? const Radius.circular(30)
                        : const Radius.circular(10),
                    bottom: isLast
                        ? const Radius.circular(30)
                        : const Radius.circular(10),
                  ),
                );
              }),
                 const SizedBox(height: 32),
            ],
          ],
        );
      },
    );
  }
}

// ── Theme card (Store) ────────────────────────────────────────────────────────

class _ThemeCard extends StatelessWidget {
  final ExtensionThemeMeta meta;
  final BorderRadiusGeometry borderRadius;
  const _ThemeCard({required this.meta, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        final installed = prov.isInstalled(meta.id);
        final downloading = prov.isDownloading(meta.id);
        final active = prov.isActive(meta.id);
        final colors = Theme.of(context).colorScheme;

        return Card(
          elevation: 0,
          color: colors.surfaceTint.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: _ThemeAvatar(meta: meta),
            title: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Flexible(
                    child: Text(meta.name,
                        style:
                            const TextStyle(fontWeight: FontWeight.w500)),
                  ),
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
                              fontSize: 10,
                              color: colors.onPrimaryContainer)),
                    ),
                  ],
                ],
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                meta.dark ? 'Dark theme' : 'Light theme',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
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
                        onPressed: () =>
                            _showOptions(context, prov, meta, active),
                      )
                    : IconButton(
                        icon: const Icon(Icons.download_outlined),
                        tooltip: 'Install',
                        onPressed: () =>
                            _confirmInstall(context, prov, meta),
                      ),
          ),
        );
      },
    );
  }

  void _confirmInstall(BuildContext context, ExtensionsProvider prov,
      ExtensionThemeMeta meta) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Install "${meta.name}"?'),
        content: const Text('The theme will be saved to your device.'),
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
                      content: Text('"${meta.name}" installed!'),
                      behavior: SnackBarBehavior.floating));
                }
              });
            },
            child: const Text('Install'),
          ),
        ],
      ),
    );
  }

  void _showOptions(BuildContext context, ExtensionsProvider prov,
      ExtensionThemeMeta meta, bool active) {
    final colors = Theme.of(context).colorScheme;
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
              active
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off,
              color: active ? colors.primary : null,
            ),
            title:
                Text(active ? 'Deactivate theme' : 'Activate theme'),
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
            leading:
                const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete',
                style: TextStyle(color: Colors.red)),
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

// ── Installed card ────────────────────────────────────────────────────────────

class _InstalledCard extends StatelessWidget {
  final ExtensionThemeMeta meta;
  final BorderRadiusGeometry borderRadius;
  const _InstalledCard(
      {required this.meta, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        final active = prov.isActive(meta.id);
        final colors = Theme.of(context).colorScheme;

        return Card(
          elevation: 0,
          color: active
              ? colors.primaryContainer.withValues(alpha: 0.3)
              : colors.surfaceTint.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(borderRadius: borderRadius),
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            leading: _ThemeAvatar(meta: meta),
            title: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(meta.name,
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                meta.dark ? 'Dark theme' : 'Light theme',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: active,
                  onChanged: (val) => val
                      ? prov.activateTheme(meta.id)
                      : prov.deactivateTheme(),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.grey, size: 20),
                  tooltip: 'Delete',
                  onPressed: () =>
                      _confirmDelete(context, prov, meta),
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
        content: const Text('The theme will be removed from your device.'),
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

// ── SDK content ───────────────────────────────────────────────────────────────

class _SdkContent extends StatelessWidget {
  const _SdkContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        if (prov.loadingSdkIndex && prov.availableSdks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        if (prov.sdkIndexError != null && prov.availableSdks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 40, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(prov.sdkIndexError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: prov.fetchSdkIndex,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry'),
                  ),
                  
                ],
              ),
            ),
          );
        }

        if (prov.availableSdks.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text('No SDKs available.')),
          );
        }

        final sdks = prov.availableSdks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sdks.asMap().entries.map((e) {
            final i = e.key;
            final isFirst = i == 0;
            final isLast = i == sdks.length - 1;
            return _SdkCard(
              ext: e.value,
              borderRadius: BorderRadius.vertical(
                top: isFirst
                    ? const Radius.circular(30)
                    : const Radius.circular(10),
                bottom: isLast
                    ? const Radius.circular(30)
                    : const Radius.circular(10),
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _SdkCard extends StatelessWidget {
  final SdkExtension ext;
  final BorderRadiusGeometry borderRadius;
  const _SdkCard({required this.ext, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final installed = ext.isInstalled;

    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.extension_rounded,
                      size: 20, color: colors.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ext.displayName,
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          _MiniChip(label: 'v${ext.sdkVersion}', colors: colors),
                          _MiniChip(label: ext.package.type.toUpperCase(), colors: colors),
                          _MiniChip(label: ext.package.arch, colors: colors),
                        ],
                      ),
                    ],
                  ),
                ),
                if (installed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_rounded,
                            size: 11, color: colors.primary),
                        const SizedBox(width: 3),
                        Text('Installed',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: colors.primary)),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            // Description
            Text(ext.description,
                style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.6),
                    height: 1.45)),
            const SizedBox(height: 10),
            // Footer row
            Row(
              children: [
                Icon(Icons.person_outline_rounded,
                    size: 13,
                    color: colors.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Text(ext.packageAuthor.name,
                    style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurface.withValues(alpha: 0.5))),
                const SizedBox(width: 10),
                Icon(Icons.edit_outlined,
                    size: 13,
                    color: colors.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Text('${ext.jsonAuthor.name} · ${ext.jsonAuthor.date}',
                    style: TextStyle(
                        fontSize: 11,
                        color: colors.onSurface.withValues(alpha: 0.5))),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () =>
                      showSdkExtensionInstallDialog(context, ext),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  icon: Icon(
                    installed
                        ? Icons.update_rounded
                        : Icons.download_rounded,
                    size: 14,
                  ),
                  label: Text(installed ? 'Update' : 'Install'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  const _MiniChip({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceTint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.6))),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

/// CircleAvatar with theme background + accent-colored icon.
class _ThemeAvatar extends StatelessWidget {
  final ExtensionThemeMeta meta;
  const _ThemeAvatar({required this.meta});

  @override
  Widget build(BuildContext context) {
    final bg = Color(meta.previewArgb);
    final accent = Color(meta.accentArgb);
    return CircleAvatar(
      backgroundColor: bg,
      child: FaIcon(
        meta.dark ? FontAwesomeIcons.moon : FontAwesomeIcons.sun,
        size: 14,
        color: accent,
      ),
    );
  }
}

Widget _sectionLabel(BuildContext context, String label) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      label,
      style: TextStyle(
       color: Colors.grey,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    ),
  );
}
