import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:rootfs_manager/rootfs_manager.dart';

import '../providers/settings_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _page = 0;
  bool _storageGranted = false;
  bool _installGranted = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final storage = await Permission.storage.status;
    final install = await Permission.requestInstallPackages.status;
    if (!mounted) return;
    setState(() {
      _storageGranted = storage.isGranted;
      _installGranted = install.isGranted;
    });
  }

  Future<void> _requestStorage() async {
    final status = await Permission.storage.request();
    if (!mounted) return;
    setState(() => _storageGranted = status.isGranted);
  }

  Future<void> _requestInstall() async {
    final status = await Permission.requestInstallPackages.request();
    if (!mounted) return;
    setState(() => _installGranted = status.isGranted);
  }

  void _next() => setState(() => _page++);
  void _back() => setState(() => _page--);

  Future<void> _finish() async {
    await context.read<SettingsProvider>().setOnboardingDone();
  }

  bool get _canProceedPage1 => _storageGranted && _installGranted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootfs = context.watch<RootfsProvider>();

    final isInstalling = _page == 2 &&
        (rootfs.state == RootfsState.downloading ||
            rootfs.state == RootfsState.extracting);

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          // ── Page content fills all available space ──────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position:
                      Tween(begin: const Offset(0.08, 0), end: Offset.zero)
                          .animate(anim),
                  child: child,
                ),
              ),
              child: KeyedSubtree(
                key: ValueKey(_page),
                child: switch (_page) {
                  0 => const _WelcomePage(),
                  1 => _PermissionsPage(
                      storageGranted: _storageGranted,
                      installGranted: _installGranted,
                      onRequestStorage: _requestStorage,
                      onRequestInstall: _requestInstall,
                    ),
                  _ => _BootstrapPage(rootfs: rootfs),
                },
              ),
            ),
          ),
          // ── Bottom nav bar pinned to the very bottom ────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: _page > 0 && !isInstalling
                        ? TextButton(
                            onPressed: _back,
                            child:
                                const Icon(Icons.arrow_back_ios_new_rounded),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        3,
                        (i) => _OnboardingDot(active: i == _page),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _page == 0
                          ? _NavButton(
                              onPressed: _next,
                              icon: Icons.arrow_forward_ios_rounded,
                            )
                          : _page == 1
                              ? _NavButton(
                                  onPressed:
                                      _canProceedPage1 ? _next : null,
                                  icon: Icons.arrow_forward_ios_rounded,
                                )
                              : _NavButton(
                                  onPressed:
                                      rootfs.isReady ? _finish : null,
                                  icon: Icons.arrow_forward_ios_rounded,
                                ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

// ── Welcome page ──────────────────────────────────────────────────────────────

class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(height: 100,),
          Image.asset('assets/logo.png', width: 300, height: 300, color: Theme.of(context).textTheme.bodyLarge?.color),
          const SizedBox(height: 32),
          Text(
            'Imagine, Desenvolva, Crie.',
            textAlign: TextAlign.center,
            style: TextStyle(
               fontWeight: FontWeight.w500,
              fontSize: 18,
             // fontWeight: FontWeight.w800,
             
            ),
          ),
        
          Text(
            'Tudo no seu Android.',
            textAlign: TextAlign.center,
            style: TextStyle(
         color: cs.onSurface,
              fontSize: 18,
             
            ),
          ),
        ],
      ),
    );
  }
}

// ── Permissions page ─────────────────────────────────────────────────────────

class _PermissionsPage extends StatelessWidget {
  final bool storageGranted;
  final bool installGranted;
  final VoidCallback onRequestStorage;
  final VoidCallback onRequestInstall;

  const _PermissionsPage({
    required this.storageGranted,
    required this.installGranted,
    required this.onRequestStorage,
    required this.onRequestInstall,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 100,),
          Text(
            'Permissões',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Algumas permissões são necessárias para o funcionamento correto do app.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 28),
          _PermissionTile(
            icon: Icons.folder_rounded,
            iconColor: Colors.orange,
            title: 'Armazenamento',
            subtitle: 'Necessário para acessar e salvar projetos no dispositivo.',
            granted: storageGranted,
            onRequest: onRequestStorage,
            topRounded: true,
            bottomRounded: false,
          ),
          const SizedBox(height: 2),
          _PermissionTile(
            icon: Icons.install_mobile_rounded,
            iconColor: Colors.blue,
            title: 'Instalar aplicativos',
            subtitle: 'Necessário para instalar APKs gerados pelo app.',
            granted: installGranted,
            onRequest: onRequestInstall,
            topRounded: false,
            bottomRounded: true,
          ),
        ],
      ),
    ));
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onRequest;
  final bool topRounded;
  final bool bottomRounded;

  const _PermissionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onRequest,
    required this.topRounded,
    required this.bottomRounded,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final radius = BorderRadius.vertical(
      top: topRounded ? const Radius.circular(20) : const Radius.circular(4),
      bottom:
          bottomRounded ? const Radius.circular(20) : const Radius.circular(4),
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceTint.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: radius),
      child: InkWell(
        onTap: granted ? null : onRequest,
        borderRadius: radius,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: iconColor.withValues(alpha: 0.15),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style:
                          TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              granted
                  ? Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.check_rounded,
                              size: 14, color: Colors.green),
                          const SizedBox(width: 4),
                          Text(
                            'Concedida',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'Permitir',
                        style: TextStyle(
                          color: cs.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bootstrap page ────────────────────────────────────────────────────────────

class _BootstrapPage extends StatelessWidget {
  final RootfsProvider rootfs;

  const _BootstrapPage({required this.rootfs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox.expand(
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 40, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 100,),
          Text(
            'Ambiente',
            style: TextStyle(
              color: cs.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'O Bootstrap instala o ambiente Linux necessário para compilar e executar projetos.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
          ),
          const SizedBox(height: 28),
          _BootstrapCard(rootfs: rootfs),
        ],
      ),
    ));
  }
}

class _BootstrapCard extends StatelessWidget {
  final RootfsProvider rootfs;

  const _BootstrapCard({required this.rootfs});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = rootfs.state;
    final isActive = state == RootfsState.downloading ||
        state == RootfsState.extracting;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: cs.surfaceTint.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: cs.primary.withValues(alpha: 0.15),
                  child: Icon(Icons.terminal_rounded,
                      color: cs.primary, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bootstrap (Termux)',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Ambiente Linux para ARM64',
                        style: TextStyle(
                            color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                if (state == RootfsState.ready)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded,
                            size: 14, color: Colors.green),
                        const SizedBox(width: 4),
                        Text(
                          'Instalado',
                          style: TextStyle(
                            color: Colors.green.shade700,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            // Progress area
            if (isActive) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: rootfs.progress > 0 ? rootfs.progress : null,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 8),
              Text(
                rootfs.statusMessage,
                style:
                    TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],

            if (state == RootfsState.error) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: cs.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        rootfs.error ?? 'Erro desconhecido',
                        style:
                            TextStyle(color: cs.onErrorContainer, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Action button
            if (state != RootfsState.ready) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: isActive
                      ? null
                      : () => state == RootfsState.error
                          ? rootfs.retry()
                          : rootfs.downloadAndInstall(),
                  child: Text(
                    state == RootfsState.error
                        ? 'Tentar novamente'
                        : 'Instalar Bootstrap',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _OnboardingDot extends StatelessWidget {
  final bool active;

  const _OnboardingDot({required this.active});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? cs.primary : cs.outlineVariant,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;

  const _NavButton({required this.onPressed, required this.icon});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
        shape: const CircleBorder(),
      ),
      child: Icon(icon),
    );
  }
}
