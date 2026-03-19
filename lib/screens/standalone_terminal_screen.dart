import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:terminal_pkg/terminal_pkg.dart';

// ── Standalone terminal ───────────────────────────────────────────────────────

class StandaloneTerminalScreen extends StatefulWidget {
  const StandaloneTerminalScreen({super.key});

  @override
  State<StandaloneTerminalScreen> createState() =>
      StandaloneTerminalScreenState();
}

class StandaloneTerminalScreenState extends State<StandaloneTerminalScreen> {
  final _termProvider = TerminalProvider();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _termProvider.createSession(
        label: 'bash 1',
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
    final colors = Theme.of(context).colorScheme;

    return ChangeNotifierProvider.value(
      value: _termProvider,
      child: Consumer<TerminalProvider>(
        builder: (context, provider, _) {
          return Scaffold(
            key: _scaffoldKey,
            backgroundColor: colors.surface,

            // ── Sessions drawer ──────────────────────────────────────────
            drawer: _SessionsDrawer(provider: provider),

            body: Column(
              children: [
                // ── Top bar ───────────────────────────────────────────────
                _TerminalAppBar(
                  provider: provider,
                  onMenuTap: () =>
                      _scaffoldKey.currentState?.openDrawer(),
                ),

                // ── Session chips ─────────────────────────────────────────
                if (provider.sessions.isNotEmpty)
                  _SessionTabBar(provider: provider),

                // ── Terminal body ─────────────────────────────────────────
                Expanded(
                  child: TerminalTabs(
                    initialWorkDir: RuntimeEnvir.homePath,
                  ),
                ),

                // ── Keys bar (padded above system nav bar) ─────────────────
                if (provider.active != null)
                  SafeArea(
                    top: false,
                    child: XtermBottomBar(
                      pseudoTerminal: provider.active!.pty!,
                      terminal: provider.active!.terminal,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Sessions drawer ───────────────────────────────────────────────────────────

class _SessionsDrawer extends StatelessWidget {
  final TerminalProvider provider;
  const _SessionsDrawer({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Drawer(
      backgroundColor: colors.surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  Icon(Icons.terminal, size: 18, color: colors.primary),
                  const SizedBox(width: 10),
                  Text(
                    'Sessions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  const Spacer(),
                  _DrawerChip(
                    icon: Icons.add,
                    label: 'New',
                    onTap: () {
                      provider.createSession(
                          workingDirectory: RuntimeEnvir.homePath);
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),

            Divider(
                height: 1,
                color: colors.outline.withValues(alpha: 0.15),
                indent: 16,
                endIndent: 16),
            const SizedBox(height: 8),

            // Session list
            Expanded(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                itemCount: provider.sessions.length,
                itemBuilder: (context, i) {
                  final isActive = provider.activeIndex == i;
                  final session = provider.sessions[i];
                  return _DrawerSessionTile(
                    label: session.label,
                    isActive: isActive,
                    isFirst: i == 0,
                    isLast: i == provider.sessions.length - 1,
                    onTap: () {
                      provider.switchTo(i);
                      Navigator.of(context).pop();
                    },
                    onClose: provider.sessions.length > 1
                        ? () => provider.closeSession(i)
                        : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _DrawerChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: colors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.primary),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: colors.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _DrawerSessionTile extends StatelessWidget {
  final String label;
  final bool isActive;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _DrawerSessionTile({
    required this.label,
    required this.isActive,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.vertical(
      top: Radius.circular(isFirst ? 20 : 8),
      bottom: Radius.circular(isLast ? 20 : 8),
    );

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: isActive
            ? colors.primary.withValues(alpha: 0.15)
            : colors.surfaceTint.withValues(alpha: 0.08),
        borderRadius: radius,
        border: isActive
            ? Border.all(color: colors.primary.withValues(alpha: 0.35))
            : null,
      ),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: radius),
        leading: Icon(
          Icons.terminal,
          size: 18,
          color: isActive
              ? colors.primary
              : colors.onSurface.withValues(alpha: 0.55),
        ),
        title: Text(
          label,
          style: TextStyle(
            color: isActive ? colors.primary : Colors.white,
            fontWeight:
                isActive ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
        trailing: onClose != null
            ? IconButton(
                icon: Icon(Icons.close,
                    size: 16,
                    color: colors.onSurface.withValues(alpha: 0.4)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onClose,
              )
            : null,
        onTap: onTap,
      ),
    );
  }
}

// ── App bar ───────────────────────────────────────────────────────────────────

class _TerminalAppBar extends StatelessWidget {
  final TerminalProvider provider;
  final VoidCallback onMenuTap;
  const _TerminalAppBar(
      {required this.provider, required this.onMenuTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeLabel = provider.active?.label ?? 'Terminal';

    return SafeArea(
      bottom: false,
      child: Container(
        height: kToolbarHeight,
        color: colors.surface,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
          
            // Sessions drawer button
            IconButton(
              icon: Icon(Icons.menu_rounded,
                  size: 22, color: colors.onSurface),
              onPressed: onMenuTap,
              tooltip: 'Sessions',
            ),
            const SizedBox(width: 2),
            // Terminal icon + title
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: colors.surfaceTint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terminal, size: 15, color: colors.primary),
                  const SizedBox(width: 6),
                  Text(
                    activeLabel,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // New session
            _ActionChip(
              icon: Icons.add,
              label: 'New',
              onTap: () => provider.createSession(
                workingDirectory: RuntimeEnvir.homePath,
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionChip(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colors.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: colors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: colors.primary),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: colors.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ── Session tab bar ───────────────────────────────────────────────────────────

class _SessionTabBar extends StatelessWidget {
  final TerminalProvider provider;
  const _SessionTabBar({required this.provider});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      height: 44,
      color: colors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: provider.sessions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final isActive = i == provider.activeIndex;
          final session = provider.sessions[i];
          return _SessionChip(
            label: session.label,
            isActive: isActive,
            onTap: () => provider.switchTo(i),
            onClose: provider.sessions.length > 1
                ? () => provider.closeSession(i)
                : null,
          );
        },
      ),
    );
  }
}

class _SessionChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback? onClose;

  const _SessionChip({
    required this.label,
    required this.isActive,
    required this.onTap,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: isActive
            ? colors.primary
            : colors.surfaceTint.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: isActive
            ? null
            : Border.all(
                color: colors.outline.withValues(alpha: 0.2)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: EdgeInsets.only(
              left: 12,
              right: onClose != null ? 6 : 12,
              top: 2,
              bottom: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.terminal,
                size: 13,
                color: isActive
                    ? colors.onPrimary
                    : colors.onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isActive
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: isActive
                      ? colors.onPrimary
                      : colors.onSurface.withValues(alpha: 0.75),
                ),
              ),
              if (onClose != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onClose,
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: isActive
                        ? colors.onPrimary.withValues(alpha: 0.7)
                        : colors.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
