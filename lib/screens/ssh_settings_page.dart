import 'package:fl_ide/widgets/settings_page_widgets.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ssh_pkg/ssh_pkg.dart';

import '../l10n/app_strings.dart';
import '../providers/settings_provider.dart';
import '../widgets/animated_toggle.dart';

class SshSettingsPage extends StatefulWidget {
  const SshSettingsPage({super.key});

  @override
  State<SshSettingsPage> createState() => _SshSettingsPageState();
}

class _SshSettingsPageState extends State<SshSettingsPage> {
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _usernameCtrl;
  late final TextEditingController _passwordCtrl;
  late final TextEditingController _keyPathCtrl;
  late final TextEditingController _projectsPathCtrl;

  bool _obscurePassword = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final sp = context.read<SettingsProvider>();
    _hostCtrl         = TextEditingController(text: sp.sshHost);
    _portCtrl         = TextEditingController(text: sp.sshPort.toString());
    _usernameCtrl     = TextEditingController(text: sp.sshUsername);
    _passwordCtrl     = TextEditingController(text: sp.sshPassword);
    _keyPathCtrl      = TextEditingController(text: sp.sshKeyPath);
    _projectsPathCtrl = TextEditingController(
        text: sp.sshProjectsPath.isEmpty ? '~/projects' : sp.sshProjectsPath);
  }

  @override
  void dispose() {
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _keyPathCtrl.dispose();
    _projectsPathCtrl.dispose();
    super.dispose();
  }

  // ── Persist on focus-lost / done ─────────────────────────────────────────

  void _saveAll() {
    final sp = context.read<SettingsProvider>();
    sp.setSshHost(_hostCtrl.text.trim());
    final port = int.tryParse(_portCtrl.text.trim()) ?? 22;
    sp.setSshPort(port);
    sp.setSshUsername(_usernameCtrl.text.trim());
    sp.setSshPassword(_passwordCtrl.text);
    sp.setSshKeyPath(_keyPathCtrl.text.trim());
    sp.setSshProjectsPath(_projectsPathCtrl.text.trim());
  }

  // ── Test connection ───────────────────────────────────────────────────────

  Future<void> _testConnection() async {
    _saveAll();
    final sp = context.read<SettingsProvider>();
    final sshProv = context.read<SshProvider>();

    final config = SshConfig(
      host: sp.sshHost,
      port: sp.sshPort,
      username: sp.sshUsername,
      password: sp.sshUseKey ? null : sp.sshPassword,
      privateKeyPath: sp.sshUseKey ? sp.sshKeyPath : null,
      useKeyAuth: sp.sshUseKey,
      remoteProjectsPath: sp.sshProjectsPath.isEmpty
          ? '~/projects'
          : sp.sshProjectsPath,
      enabled: sp.sshEnabled,
    );

    setState(() => _testing = true);
    await sshProv.connect(config);
    setState(() => _testing = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final sp = context.watch<SettingsProvider>();

    return SettingsPageScaffold(
      title: s.ssh,
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // ── Enable SSH ────────────────────────────────────────────────────
          _switchTile(
            context,
            title: s.sshEnabled,
            subtitle: s.sshEnabledSub,
            value: sp.sshEnabled,
            onChanged: (v) => sp.setSshEnabled(v),
            iconBg: Colors.indigo,
            icon: FontAwesomeIcons.server,
            borderRadius: const BorderRadius.all(Radius.circular(24)),
          ),
          const SizedBox(height: 8),
      
          // ── Connection status banner (shown when connected) ───────────────
          Consumer<SshProvider>(
            builder: (context, sshProv, _) {
              if (!sshProv.isConnected) return const SizedBox.shrink();
              final colors = Theme.of(context).colorScheme;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.computer_rounded,
                            size: 16, color: Colors.green),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            sshProv.connectedSystemInfo ??
                                sshProv.config?.host ??
                                '',
                            style: const TextStyle(
                                color: Colors.green, fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sshProv.detectedSdks.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: sshProv.detectedSdks
                          .map((sdk) => Chip(
                                label: Text(sdk,
                                    style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                backgroundColor:
                                    colors.secondaryContainer.withValues(alpha: 0.6),
                                side: BorderSide.none,
                                padding: EdgeInsets.zero,
                              ))
                          .toList(),
                    ),
                  ],
                  const SizedBox(height: 8),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
      
          // ── Connection ────────────────────────────────────────────────────
          _sectionHeader(context,s.sshSection),
          _textFieldTile(
            context,
            label: s.sshHost,
            controller: _hostCtrl,
            icon: FontAwesomeIcons.networkWired,
            hint: '192.168.1.100',
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            onSubmitted: (_) => _saveAll(),
          ),
          _textFieldTile(
            context,
            label: s.sshPort,
            controller: _portCtrl,
            icon: FontAwesomeIcons.plug,
            hint: '22',
            keyboardType: TextInputType.number,
            onSubmitted: (_) => _saveAll(),
          ),
          _textFieldTile(
            context,
            label: s.sshUsername,
            controller: _usernameCtrl,
            icon: FontAwesomeIcons.user,
            hint: 'user',
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(20)),
            onSubmitted: (_) => _saveAll(),
          ),
          const SizedBox(height: 16),
      
          // ── Auth type ─────────────────────────────────────────────────────
          _sectionHeader(context,s.sshUseKey),
          _authTypeTile(context, sp, s),
          const SizedBox(height: 16),
      
          // ── Credential ────────────────────────────────────────────────────
          if (!sp.sshUseKey) ...[
            _sectionHeader(context,s.sshPasswordAuth),
            _passwordTile(context, s),
            const SizedBox(height: 16),
          ] else ...[
            _sectionHeader(context,s.sshKeyAuth),
            _textFieldTile(
              context,
              label: s.sshKeyPath,
              controller: _keyPathCtrl,
              icon: FontAwesomeIcons.key,
              hint: '~/.ssh/id_rsa',
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              onSubmitted: (_) => _saveAll(),
            ),
            const SizedBox(height: 16),
          ],
      
          // ── Remote projects path ──────────────────────────────────────────
          _sectionHeader(context,s.sshRemoteProjectsPath),
          _textFieldTile(
            context,
            label: s.sshRemoteProjectsPath,
            controller: _projectsPathCtrl,
            icon: FontAwesomeIcons.folderOpen,
            hint: '~/projects',
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            onSubmitted: (_) => _saveAll(),
          ),
          const SizedBox(height: 16),
      
          // ── Status ────────────────────────────────────────────────────────
          Consumer<SshProvider>(
            builder: (context, sshProv, _) =>
                _statusTile(context, sshProv, s),
          ),
          const SizedBox(height: 16),
      
          // ── Connect / Disconnect button ───────────────────────────────────
          Consumer<SshProvider>(
            builder: (context, sshProv, _) =>
                _connectButton(context, sshProv, s),
          ),
          const SizedBox(height: 12),
      
          // ── Test connection button ────────────────────────────────────────
          _testButton(context, s),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  // ── Widget helpers ────────────────────────────────────────────────────────

  Widget _sectionHeader(BuildContext context, String title) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        title,
        style:  TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: colors.primary,
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
   // final colors = Theme.of(context).colorScheme;
  //  final card = Theme.of(context).cardTheme;
    return Card(
     // elevation: 0,
    //  color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: ListTile(
        minTileHeight: 50, 
        leading:
            CircleAvatar(backgroundColor: iconBg, child: FaIcon(icon, size: 16, color: Colors.white)),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: SizedBox(
          width: 51,
          height: 30,
          child: AnimatedToggle(value: value, onChanged: onChanged),
        ),
        onTap: () => onChanged(!value),
      ),
    );
  }

  Widget _authTypeTile(
      BuildContext context, SettingsProvider sp, AppStrings s) {
    final colors = Theme.of(context).colorScheme;
   // final card = Theme.of(context).cardTheme;
    return Card(
      //elevation: 0,
    //  color: card.color?.withOpacity(0.5),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        children: [
          RadioListTile<bool>(
            title: Text(s.sshPasswordAuth),
            value: false,
            groupValue: sp.sshUseKey,
            onChanged: (v) => sp.setSshUseKey(false),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          Divider(
              height: 1,
              thickness: 0.5,
              color: colors.outline.withValues(alpha: 0.2)),
          RadioListTile<bool>(
            title: Text(s.sshKeyAuth),
            value: true,
            groupValue: sp.sshUseKey,
            onChanged: (v) => sp.setSshUseKey(true),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
        ],
      ),
    );
  }

  Widget _textFieldTile(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required IconData icon,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    BorderRadiusGeometry borderRadius = BorderRadius.zero,
    ValueChanged<String>? onSubmitted,
  }) {
  //  final colors = Theme.of(context).colorScheme;
    //final card = Theme.of(context).cardTheme;
    return Card(
   //   elevation: 0,
   //  color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      margin: const EdgeInsets.symmetric(vertical: 1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.indigo,
              radius: 18,
              child: FaIcon(icon, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: controller,
                keyboardType: keyboardType,
                decoration: InputDecoration(
                  labelText: label,
                  hintText: hint,
                  border: InputBorder.none,
                  isDense: true,
                  disabledBorder: InputBorder.none,
                ),
                
                onSubmitted: onSubmitted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _passwordTile(BuildContext context, AppStrings s) {
  //  final colors = Theme.of(context).colorScheme;
    // final card = Theme.of(context).cardTheme;
    return Card(
    //  elevation: 0,
     //  color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.indigo,
              radius: 18,
              child:
                  const FaIcon(FontAwesomeIcons.lock, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _passwordCtrl,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: s.sshPassword,
                  border: InputBorder.none,
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
                onSubmitted: (_) => _saveAll(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusTile(
      BuildContext context, SshProvider sshProv, AppStrings s) {
  //  final colors = Theme.of(context).colorScheme;
   // final card = Theme.of(context).cardTheme;
    final (label, color, icon) = switch (sshProv.status) {
      SshStatus.connected    => (s.sshConnected,    Colors.green,  Icons.check_circle_outline),
      SshStatus.connecting   => (s.sshConnecting,   Colors.orange, Icons.sync),
      SshStatus.error        => ('${s.sshConnectionFailed}: ${sshProv.error ?? ""}', Colors.red, Icons.error_outline),
      SshStatus.disconnected => (s.sshDisconnected, Colors.grey,   Icons.cloud_off_outlined),
    };

    return Card(
      //elevation: 0,
    //   color: card.color?.withOpacity(0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label,
            style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        trailing: sshProv.status == SshStatus.connected
            ? TextButton(
                onPressed: () => sshProv.disconnect(),
                child: const Text('Disconnect'),
              )
            : null,
      ),
    );
  }

  Widget _connectButton(
      BuildContext context, SshProvider sshProv, AppStrings s) {
    final colors = Theme.of(context).colorScheme;
    final isConnected = sshProv.isConnected;
    final isConnecting = sshProv.status == SshStatus.connecting;

    return SizedBox(
      width: double.infinity,
      child: isConnected
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => sshProv.disconnect(),
              icon: const Icon(Icons.link_off, size: 16),
              label: const Text('Disconnect'),
            )
          : FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.secondary,
                foregroundColor: colors.onSecondary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: isConnecting ? null : _connectNow,
              icon: isConnecting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link, size: 16),
              label: Text(isConnecting ? s.sshConnecting : 'Connect'),
            ),
    );
  }

  Future<void> _connectNow() async {
    _saveAll();
    final sp = context.read<SettingsProvider>();
    final sshProv = context.read<SshProvider>();
    final config = SshConfig(
      host: sp.sshHost,
      port: sp.sshPort,
      username: sp.sshUsername,
      password: sp.sshUseKey ? null : sp.sshPassword,
      privateKeyPath: sp.sshUseKey ? sp.sshKeyPath : null,
      useKeyAuth: sp.sshUseKey,
      remoteProjectsPath:
          sp.sshProjectsPath.isEmpty ? '~/projects' : sp.sshProjectsPath,
      enabled: sp.sshEnabled,
    );
    await sshProv.connect(config);
  }

  Widget _testButton(BuildContext context, AppStrings s) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: colors.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        onPressed: _testing ? null : _testConnection,
        icon: _testing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const FaIcon(FontAwesomeIcons.plug, size: 16),
        label: Text(_testing ? s.sshConnecting : s.sshTestConnection),
      ),
    );
  }
}
