import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:project_manager/project_manager.dart';
import 'package:provider/provider.dart';
import 'package:sdk_manager/sdk_manager.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

import '../providers/settings_provider.dart';
import '../widgets/animated_toggle.dart';
import 'extensions_screen.dart';

// ── Home screen ───────────────────────────────────────────────────────────────

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('FL IDE'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: () => _createProject(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 70),
              ),
              child: const Text(
                'Create New Project',
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _openProjects(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 70),
              ),
              child: const Text(
                'Open Existing Project',
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _openTerminal(context),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 70),
              ),
              child: const Text(
                'Terminal',
                style: TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(200, 70),
              ),
              child: const Text(
                'Settings',
                style: TextStyle(fontSize: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createProject(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
    );
  }

  void _openProjects(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const _ProjectsSheet(),
    );
  }

  void _openTerminal(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const _StandaloneTerminalScreen()),
    );
  }
}

// ── Projects bottom sheet ─────────────────────────────────────────────────────

class _ProjectsSheet extends StatelessWidget {
  const _ProjectsSheet();

  @override
  Widget build(BuildContext context) {
    return Consumer<ProjectManagerProvider>(
      builder: (context, pm, _) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Text('Projects',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CreateProjectScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: pm.projects.isEmpty
                  ? Center(
                      child: Text('No projects yet',
                          style: Theme.of(context).textTheme.bodyMedium),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: pm.projects.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final p = pm.projects[i];
                        return ListTile(
                          leading: Text(p.sdk.icon,
                              style: const TextStyle(fontSize: 24)),
                          title: Text(p.name),
                          subtitle: Text(p.sdk.displayName),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert, size: 20),
                            onPressed: () =>
                                _showDeleteOption(context, pm, p),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            pm.openProject(p);
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteOption(
      BuildContext context, ProjectManagerProvider pm, Project p) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Open'),
            onTap: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              pm.openProject(p);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline),
            title: const Text('Delete'),
            onTap: () {
              Navigator.pop(ctx);
              pm.deleteProject(p);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ── Standalone terminal ───────────────────────────────────────────────────────

class _StandaloneTerminalScreen extends StatefulWidget {
  const _StandaloneTerminalScreen();

  @override
  State<_StandaloneTerminalScreen> createState() =>
      _StandaloneTerminalScreenState();
}

class _StandaloneTerminalScreenState
    extends State<_StandaloneTerminalScreen> {
  final _termProvider = TerminalProvider();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _termProvider.createSession(
        label: 'Terminal',
        workingDirectory: RuntimeEnvir.homePath,
      );
    });
  }

  @override
  void dispose() {
    _termProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _termProvider,
      child: Consumer<TerminalProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            drawer: Drawer(
              child: SafeArea(
                child: Column(
                  children: [
                    ListTile(
                      title: Text('Sessions',
                          style: Theme.of(context).textTheme.titleLarge),
                      trailing: const Icon(Icons.add),
                      onTap: () {
                        provider.createSession(
                          workingDirectory: RuntimeEnvir.homePath,
                        );
                        Navigator.of(context).pop();
                      },
                    ),
                    const Divider(),
                    Expanded(
                      child: ListView.builder(
                        itemCount: provider.sessions.length,
                        itemBuilder: (context, i) {
                          final isSelected = provider.activeIndex == i;
                          final colors = Theme.of(context).colorScheme;
                          return Card(
                            color: isSelected
                                ? colors.secondaryContainer
                                : colors.surfaceContainerHighest,
                            margin: const EdgeInsets.symmetric(
                                vertical: 2, horizontal: 5),
                            child: ListTile(
                              title: Text(
                                provider.sessions[i].label,
                                style: TextStyle(
                                  color: isSelected
                                      ? colors.onSecondaryContainer
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                              selected: isSelected,
                              onTap: () {
                                provider.switchTo(i);
                                Navigator.of(context).pop();
                              },
                              onLongPress: () async {
                                final shouldDelete = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                        'Close ${provider.sessions[i].label}?'),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(false),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.of(ctx).pop(true),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  ),
                                );
                                if (shouldDelete == true) {
                                  provider.closeSession(i);
                                }
                              },
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            appBar: AppBar(
              title: const Text('Terminal'),
              leading: Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: TerminalTabs(
                      initialWorkDir: RuntimeEnvir.homePath,
                    ),
                  ),
                  if (provider.active != null)
                    XtermBottomBar(
                      pseudoTerminal: provider.active!.pty!,
                      terminal: provider.active!.terminal,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Settings screen ───────────────────────────────────────────────────────────

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: const _SettingsScreenBody(),
    );
  }
}

class _SettingsScreenBody extends StatelessWidget {
  const _SettingsScreenBody();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const double maxExtent = 140.0;
    const double minExtent = kToolbarHeight;
    const double expandedLeft = 20.0;
    const double collapsedLeft = 60.0;
    const double expandedBottom = 0.0;
    const double collapsedBottom = 8.0;

    return Consumer<SettingsProvider>(
      builder: (context, vm, _) {
        return PopScope(
          canPop: vm.currentPage == SettingsPage.main,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) vm.goBack();
          },
          child: Scaffold(
            backgroundColor: colors.surface,
            body: CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: maxExtent,
                  floating: false,
                  pinned: true,
                  backgroundColor: colors.surface,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: colors.onSurface),
                    onPressed: () {
                      if (vm.currentPage == SettingsPage.main) {
                        Navigator.of(context).pop();
                      } else {
                        vm.goBack();
                      }
                    },
                  ),
                  flexibleSpace: LayoutBuilder(
                    builder: (context, constraints) {
                      final double currentHeight = constraints.biggest.height;
                      double t = (currentHeight - minExtent) /
                          (maxExtent - minExtent);
                      t = t.clamp(0.0, 1.0);
                      final double left = expandedLeft +
                          (collapsedLeft - expandedLeft) * (1 - t);
                      final double bottom = expandedBottom +
                          (collapsedBottom - expandedBottom) * (1 - t);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          DecoratedBox(
                              decoration:
                                  BoxDecoration(color: colors.surface)),
                          Positioned(
                            left: left,
                            bottom: bottom,
                            child: const Padding(
                              padding: EdgeInsets.only(top: 16, bottom: 8),
                              child: Text(
                                'Settings',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // ── Main settings page ────────────────────────────────────
                if (vm.currentPage == SettingsPage.main) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        _buildOption(context,
                            title: 'General',
                            subtitle:
                                'Appearance and behavior settings.',
                            onTap: () =>
                                vm.navigateToPage(SettingsPage.general),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(30),
                                bottom: Radius.circular(10)),
                            iconBg: Colors.pink,
                            icon: FontAwesomeIcons.gear),
                        _buildOption(context,
                            title: 'Editor',
                            subtitle: 'Code editor preferences.',
                            onTap: () =>
                                vm.navigateToPage(SettingsPage.editor),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                                bottom: Radius.circular(10)),
                            iconBg: Colors.blue,
                            icon: FontAwesomeIcons.code),
                        _buildOption(context,
                            title: 'Terminal',
                            subtitle: 'Built-in terminal settings.',
                            onTap: () =>
                                vm.navigateToPage(SettingsPage.terminal),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                                bottom: Radius.circular(10)),
                            iconBg: Colors.black,
                            icon: FontAwesomeIcons.terminal),
                        _buildOption(context,
                            title: 'Run & Debug',
                            subtitle: 'SDKs and build options.',
                            onTap: () =>
                                vm.navigateToPage(SettingsPage.runDebug),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                                bottom: Radius.circular(10)),
                            iconBg: Colors.orange,
                            icon: FontAwesomeIcons.bug),
                        _buildOption(context,
                            title: 'Extensions',
                            subtitle: 'Themes and add-ons.',
                            onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          const ExtensionsScreen()),
                                ),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                                bottom: Radius.circular(10)),
                            iconBg: Colors.teal,
                            icon: FontAwesomeIcons.puzzlePiece),
                        _buildOption(context,
                            title: 'About',
                            subtitle: 'App information.',
                            onTap: () =>
                                vm.navigateToPage(SettingsPage.about),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                                bottom: Radius.circular(30)),
                            iconBg: Colors.amberAccent,
                            icon: FontAwesomeIcons.circleInfo),
                        const SizedBox(height: 32),
                      ]),
                    ),
                  ),
                ],

                // ── Sub-pages ─────────────────────────────────────────────
                if (vm.currentPage != SettingsPage.main) ...[
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverToBoxAdapter(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        transitionBuilder: (child, animation) =>
                            FadeTransition(opacity: animation, child: child),
                        child: _buildPage(context, vm),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPage(BuildContext context, SettingsProvider vm) {
    final Key pageKey = ValueKey(vm.currentPage.toString());
    switch (vm.currentPage) {
      case SettingsPage.main:
        return const SizedBox.shrink();
      case SettingsPage.general:
        return Container(key: pageKey, child: _buildGeneral(context, vm));
      case SettingsPage.editor:
        return Container(key: pageKey, child: _buildEditor(context, vm));
      case SettingsPage.fileExplorer:
        return Container(key: pageKey, child: _buildFileExplorer(context));
      case SettingsPage.terminal:
        return Container(key: pageKey, child: _buildTerminal(context));
      case SettingsPage.runDebug:
        return Container(key: pageKey, child: _buildRunDebug(context));
      case SettingsPage.extensions:
        return const SizedBox.shrink(); // handled via direct push
      case SettingsPage.about:
        return Container(key: pageKey, child: _buildAbout(context));
    }
  }

  // ── General settings ──────────────────────────────────────────────────────
  Widget _buildGeneral(BuildContext context, SettingsProvider vm) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('Theme & Appearance'),
        _switchTile(context,
            title: 'Follow System Theme',
            subtitle: vm.followSystemTheme
                ? 'App follows system theme'
                : 'Manual theme control',
            value: vm.followSystemTheme,
            onChanged: vm.setFollowSystemTheme,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.purple,
            icon: FontAwesomeIcons.circleHalfStroke),
        _switchTile(context,
            title: 'Dark Mode',
            subtitle: vm.useDarkMode ? 'Dark theme active' : 'Light theme active',
            value: vm.useDarkMode,
            onChanged: vm.setUseDarkMode,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.moon),
        _switchTile(context,
            title: 'AMOLED Black',
            subtitle: 'Pure black background for OLED screens',
            value: vm.useAmoled,
            onChanged: vm.setUseAmoled,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.mobileScreen),
        _switchTile(context,
            title: 'Dynamic Colors',
            subtitle: 'Use Material You colors from wallpaper',
            value: vm.useDynamicColors,
            onChanged: vm.setUseDynamicColors,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.teal,
            icon: FontAwesomeIcons.palette),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Editor settings ───────────────────────────────────────────────────────
  Widget _buildEditor(BuildContext context, SettingsProvider vm) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('Editor'),
        _buildOption(context,
            title: 'Font & Display',
            subtitle: 'Font size, family, line numbers',
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.blue,
            icon: FontAwesomeIcons.font),
        _buildOption(context,
            title: 'Indentation',
            subtitle: 'Tabs vs spaces, indent size',
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.cyan,
            icon: FontAwesomeIcons.alignLeft),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── File explorer settings ────────────────────────────────────────────────
  Widget _buildFileExplorer(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('File Explorer'),
        _buildOption(context,
            title: 'Show Hidden Files',
            subtitle: 'Display files starting with .',
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(30)),
            iconBg: Colors.indigoAccent,
            icon: FontAwesomeIcons.file),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Terminal settings ─────────────────────────────────────────────────────
  Widget _buildTerminal(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('Terminal'),
        _buildOption(context,
            title: 'Font Size',
            subtitle: 'Terminal font size',
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(10)),
            iconBg: Colors.black,
            icon: FontAwesomeIcons.terminal),
        _buildOption(context,
            title: 'Color Scheme',
            subtitle: 'Terminal color theme',
            onTap: () {},
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10), bottom: Radius.circular(30)),
            iconBg: Colors.green,
            icon: FontAwesomeIcons.paintRoller),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Run & Debug settings ──────────────────────────────────────────────────
  Widget _buildRunDebug(BuildContext context) {
    return Consumer<SdkManagerProvider>(
      builder: (context, sdk, _) {
        final installed = sdk.installedSdks;
        return ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _sectionHeader('Environment'),
            _infoTile(context,
                title: 'RootFS Path',
                subtitle: RuntimeEnvir.usrPath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folder),
            _infoTile(context,
                title: 'Home Path',
                subtitle: RuntimeEnvir.homePath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.house),
            _infoTile(context,
                title: 'Projects Path',
                subtitle: RuntimeEnvir.projectsPath,
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10), bottom: Radius.circular(10)),
                iconBg: Colors.brown,
                icon: FontAwesomeIcons.folderOpen),
            const SizedBox(height: 16),
            _sectionHeader('Installed SDKs'),
            if (installed.isEmpty)
              _infoTile(context,
                  title: 'No SDKs installed',
                  subtitle: 'Install SDKs from the workspace',
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(30), bottom: Radius.circular(30)),
                  iconBg: Colors.grey,
                  icon: FontAwesomeIcons.boxOpen)
            else
              ...installed.asMap().entries.map((e) {
                final t = e.value;
                final isFirst = e.key == 0;
                final isLast = e.key == installed.length - 1;
                return _infoTile(context,
                    title: t.displayName,
                    subtitle: sdk.version(t) ?? 'Installed',
                    borderRadius: BorderRadius.vertical(
                      top: isFirst ? const Radius.circular(30) : const Radius.circular(10),
                      bottom: isLast ? const Radius.circular(30) : const Radius.circular(10),
                    ),
                    iconBg: Colors.orange,
                    icon: FontAwesomeIcons.wrench);
              }),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  // ── About settings ────────────────────────────────────────────────────────
  Widget _buildAbout(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _sectionHeader('About'),
        _infoTile(context,
            title: 'FL IDE',
            subtitle: 'Mobile Development Environment v1.0.0',
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(30), bottom: Radius.circular(30)),
            iconBg: Colors.blueGrey,
            icon: FontAwesomeIcons.circleInfo),
        const SizedBox(height: 32),
      ],
    );
  }

  // ── Helper builders ───────────────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.grey,
        ),
      ),
    );
  }

  Widget _buildOption(
    BuildContext context, {
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(title),
        ),
        subtitle: subtitle != null
            ? Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(subtitle, maxLines: 1),
              )
            : null,
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Widget _infoTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(title),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(subtitle, maxLines: 2),
        ),
      ),
    );
  }

  Widget _switchTile(
    BuildContext context, {
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color iconBg,
    required IconData icon,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colors.surfaceTint.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        minTileHeight: 50,
        leading: CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(title),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(subtitle),
        ),
        trailing: SizedBox(
          width: 55,
          height: 34,
          child: AnimatedToggle(value: value, onChanged: onChanged),
        ),
        onTap: () => onChanged(!value),
      ),
    );
  }
}
