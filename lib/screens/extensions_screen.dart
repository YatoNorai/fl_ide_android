import 'package:fl_ide/widgets/animated_toggle.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';

import '../app.dart' show showThemedDialog;
import '../l10n/app_strings.dart';
import '../models/extension_theme_meta.dart';
import '../providers/extensions_provider.dart';
import '../widgets/settings_page_widgets.dart';


class ExtensionsSettingsPage extends StatelessWidget {
  const ExtensionsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return SettingsPageScaffold(
      title: s.extensions,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: const ExtensionsPageContent(),
    );
  }
}

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
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    // Only rebuild when animation finishes (indexIsChanging == false),
    // not on every intermediate frame during the tab slide animation.
    _tab.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    if (_tab.index != _tabIndex) {
      setState(() => _tabIndex = _tab.index);
    }
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

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
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(20),
            ),
            splashBorderRadius: BorderRadius.circular(20),
            labelStyle:
                GoogleFonts.openSans(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.openSans(fontSize: 13),
            tabs: [
              Tab(icon: const Icon(Icons.color_lens_rounded, size: 18), text: s.extStore),
              Tab(icon: const Icon(Icons.extension_outlined, size: 18), text: s.extSdks),
              Tab(icon: const Icon(Icons.download_done_outlined, size: 18), text: s.extInstalledTab),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── IndexedStack keeps all 3 tab bodies alive ───────────────────────
        // Invisible tabs are not painted but their widget trees stay in memory,
        // so returning to a tab is instant (no reload, scroll position preserved).
        IndexedStack(
          index: _tabIndex,
          children: const [
            _StoreContent(),
            _SdkContent(),
            _InstalledContent(),
          ],
        ),

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
    final s = AppStrings.of(context);
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
                      style:  GoogleFonts.openSans(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: prov.fetchIndex,
                    icon: const Icon(Icons.refresh),
                    label: Text(s.retry),
                  ),
                ],
              ),
            ),
          );
        }

        if (prov.availableThemes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(s.extNoThemes)),
          );
        }

        final dark = prov.availableThemes.where((t) => t.dark).toList();
        final light = prov.availableThemes.where((t) => !t.dark).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionLabel(context, s.extDarkThemes),
            ..._group(context, prov, dark),
            const SizedBox(height: 8),
            _sectionLabel(context, s.extLightThemes),
            ..._group(context, prov, light),
          ],
        );
      },
    );
  }

  List<Widget> _group(BuildContext context, ExtensionsProvider prov,
      List<ExtensionThemeMeta> themes) {
    return List.generate(themes.length, (i) {
      return _ThemeCard(
        key: ValueKey(themes[i].id),
        meta: themes[i],
        borderRadius: BorderRadius.vertical(
          top: i == 0 ? const Radius.circular(30) : const Radius.circular(5),
          bottom: i == themes.length - 1
              ? const Radius.circular(30)
              : const Radius.circular(5),
        ),
      );
    });
  }
}

// ── Installed content ────────────────────────────────────────────────────────

class _InstalledContent extends StatelessWidget {
  const _InstalledContent();

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Consumer<ExtensionsProvider>(
      builder: (context, prov, _) {
        if (prov.installedThemes.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.extension_outlined,
                      size: 40, color: Colors.grey),
                  const SizedBox(height: 12),
                  Text(s.extNoExtensions,
                      style:  GoogleFonts.openSans(color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(s.extGoToStore,
                      style:  GoogleFonts.openSans(
                          color: Colors.grey, fontSize: 12)),
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
              _sectionLabel(context, s.extActiveTheme),
              _InstalledCard(
                meta: activeMeta,
                borderRadius: const BorderRadius.all(Radius.circular(30)),
              ),
              const SizedBox(height: 8),
              const Divider(),
            ],
            if (inactive.isNotEmpty) ...[
              _sectionLabel(context, s.extInstalledSection),
              ...List.generate(inactive.length, (i) => _InstalledCard(
                key: ValueKey(inactive[i].id),
                meta: inactive[i],
                borderRadius: BorderRadius.vertical(
                  top: i == 0
                      ? const Radius.circular(30)
                      : const Radius.circular(5),
                  bottom: i == inactive.length - 1
                      ? const Radius.circular(30)
                      : const Radius.circular(5),
                ),
              )),
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
  const _ThemeCard({super.key, required this.meta, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // Select only the 3 booleans this card cares about — rebuilds only when
    // install/download/active state for THIS specific theme changes.
    final id = meta.id;
    final (:installed, :downloading, :active) =
        context.select<ExtensionsProvider, ({bool installed, bool downloading, bool active})>(
      (p) => (
        installed: p.isInstalled(id),
        downloading: p.isDownloading(id),
        active: p.isActive(id),
      ),
    );
    final colors = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: _ThemeAvatar(meta: meta),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Flexible(
                child: Text(meta.name,
                    style: GoogleFonts.openSans(fontWeight: FontWeight.w500)),
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
                  child: Text(s.extActive,
                      style: GoogleFonts.openSans(
                          fontSize: 10,
                          color: colors.onPrimaryContainer)),
                ),
              ],
            ],
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            meta.dark ? s.extDarkThemeLabel : s.extLightThemeLabel,
            style: GoogleFonts.openSans(fontSize: 12, color: Colors.grey),
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
                    icon: Icon(Icons.check_circle, color: colors.primary),
                    tooltip: s.extInstalled2,
                    onPressed: () => _showOptions(context, meta, active, s),
                  )
                : IconButton(
                    icon: const Icon(Icons.file_download_outlined),
                    tooltip: s.extInstall,
                    onPressed: () => _confirmInstall(context, meta, s),
                  ),
        onTap: () {
          if (installed) {
            _showOptions(context, meta, active, s);
          } else {
            _confirmInstall(context, meta, s);
          }
        },
      ),
    );
  }

  void _confirmInstall(BuildContext context,
      ExtensionThemeMeta meta, AppStrings s) {
    final prov = context.read<ExtensionsProvider>();
    showThemedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text('${s.extInstallQ} "${meta.name}"'),
               shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey, width: 0.2), borderRadius: BorderRadiusGeometry.circular(30)),
              content: Text(s.extInstallBody),
              actions: [
                TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel)),
                FilledButton(
                  onPressed: () {
            Navigator.pop(ctx);
            prov.downloadTheme(meta).then((_) {
              if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${meta.name}" ${s.extInstalled2.toLowerCase()}!'),
          behavior: SnackBarBehavior.floating));
              }
            });
                  },
                  child: Text(s.extInstall),
                ),
              ],
            ),
    );
  }

  void _showOptions(BuildContext context,
      ExtensionThemeMeta meta, bool active, AppStrings s) {
    final prov = context.read<ExtensionsProvider>();
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
    //    side: BorderSide(color: Colors.grey, width: 0.2),
        
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
            title: Text(active ? s.extDeactivate : s.extActivate),
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
            title: Text(s.delete, style:  GoogleFonts.openSans(color: Colors.red)),
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
  const _InstalledCard({super.key, required this.meta, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final active = context.select<ExtensionsProvider, bool>(
      (p) => p.isActive(meta.id),
    );
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: active
          ? colors.primaryContainer.withValues(alpha: 0.3)
          : null,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: _ThemeAvatar(meta: meta),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Text(meta.name,
              style: GoogleFonts.openSans(fontWeight: FontWeight.w500)),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 5),
          child: Text(
            meta.dark ? s.extDarkThemeLabel : s.extLightThemeLabel,
            style: GoogleFonts.openSans(fontSize: 12, color: Colors.grey),
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 51,
              height: 30,
              child: AnimatedToggle(
                value: active,
                onChanged: (val) {
                  final prov = context.read<ExtensionsProvider>();
                  if (val) {
                    prov.activateTheme(meta.id);
                  } else {
                    prov.deactivateTheme();
                  }
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.grey, size: 20),
              tooltip: s.delete,
              onPressed: () => _confirmDelete(context, meta, s),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context,
      ExtensionThemeMeta meta, AppStrings s) {
    final prov = context.read<ExtensionsProvider>();
    showThemedDialog(
      context: context,
      builder: (ctx) => AlertDialog(
              title: Text('${s.extDeleteQ.replaceAll('?', '')} "${meta.name}"?'),
              content: Text(s.extDeleteBody),
              actions: [
                TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel)),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: () {
            Navigator.pop(ctx);
            prov.deleteTheme(meta.id);
                  },
                  child: Text(s.delete),
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
    final s = AppStrings.of(context);
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
                      style:  GoogleFonts.openSans(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: prov.fetchSdkIndex,
                    icon: const Icon(Icons.refresh),
                    label: Text(s.retry),
                  ),
                ],
              ),
            ),
          );
        }

        if (prov.availableSdks.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(s.extNoSdks)),
          );
        }

        final sdks = prov.availableSdks;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(sdks.length, (i) => _SdkCard(
            key: ValueKey(sdks[i].sdk),
            ext: sdks[i],
            borderRadius: BorderRadius.vertical(
              top: i == 0
                  ? const Radius.circular(30)
                  : const Radius.circular(5),
              bottom: i == sdks.length - 1
                  ? const Radius.circular(30)
                  : const Radius.circular(5),
            ),
          )),
        );
      },
    );
  }
}

class _SdkCard extends StatelessWidget {
  final SdkExtension ext;
  final BorderRadiusGeometry borderRadius;
  const _SdkCard({super.key, required this.ext, required this.borderRadius});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);
    final installed = ext.isInstalled;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
                    borderRadius: BorderRadius.circular(5),
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
                          style:  GoogleFonts.openSans(
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
                        Text(s.extInstalled2,
                            style: GoogleFonts.openSans(
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
                style: GoogleFonts.openSans(
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
                    style: GoogleFonts.openSans(
                        fontSize: 11,
                        color: colors.onSurface.withValues(alpha: 0.5))),
                const SizedBox(width: 10),
                Icon(Icons.edit_outlined,
                    size: 13,
                    color: colors.onSurface.withValues(alpha: 0.4)),
                const SizedBox(width: 4),
                Text('${ext.jsonAuthor.name} · ${ext.jsonAuthor.date}',
                    style: GoogleFonts.openSans(
                        fontSize: 11,
                        color: colors.onSurface.withValues(alpha: 0.5))),
                const Spacer(),
                if (installed) ...[
                  FilledButton.icon(
                    onPressed: () async {
                      await showSdkExtensionUninstallDialog(context, ext);
                      if (context.mounted) {
                        context.read<ExtensionsProvider>().refreshSdkStates();
                      }
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.error,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle:  GoogleFonts.openSans(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 14),
                    label: Text(s.extUninstall),
                  ),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () async {
                      await showSdkExtensionInstallDialog(context, ext);
                      if (context.mounted) {
                        context.read<ExtensionsProvider>().refreshSdkStates();
                      }
                    },
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      textStyle:  GoogleFonts.openSans(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 14),
                    label: Text(s.extInstall),
                  ),
                ],
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
          style: GoogleFonts.openSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.6))),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────────

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
  final colors = Theme.of(context).colorScheme;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(
      label,
      style:  GoogleFonts.openSans(
        color: colors.primary,
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
    ),
  );
}
