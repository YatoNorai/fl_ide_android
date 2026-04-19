import 'dart:io';

import 'package:core/core.dart' show RuntimeEnvir, showThemedDialog;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';
import '../widgets/settings_page_widgets.dart';

class GitSettingsPage extends StatefulWidget {
  const GitSettingsPage({super.key});

  @override
  State<GitSettingsPage> createState() => _GitSettingsPageState();
}

class _GitSettingsPageState extends State<GitSettingsPage> {
  bool _gitAvailable = false;
  bool _loading = true;

  String _name   = '';
  String _email  = '';
  String _branch = 'main';

  // Remote build settings — synced from SettingsProvider
  bool   _remoteGitBuild = false;
  String _githubToken    = '';

  @override
  void initState() {
    super.initState();
    _loadConfig();
    // Load persisted remote-build settings after first frame (Provider available).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final s = context.read<SettingsProvider>();
      setState(() {
        _remoteGitBuild = s.remoteGitBuild;
        _githubToken    = s.githubToken;
      });
    });
  }

  Future<void> _loadConfig() async {
    try {
      final check = await Process.run('git', ['--version'],
          environment: RuntimeEnvir.baseEnv);
      if (check.exitCode != 0) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final name   = await _gitConfigGet('user.name');
      final email  = await _gitConfigGet('user.email');
      final branch = await _gitConfigGet('init.defaultBranch');

      if (mounted) {
        setState(() {
          _name   = name;
          _email  = email;
          _branch = branch.isEmpty ? 'main' : branch;
          _gitAvailable = true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _gitConfigGet(String key) async {
    try {
      final r = await Process.run(
        'git', ['config', '--global', key],
        environment: RuntimeEnvir.baseEnv,
      );
      return (r.stdout as String).trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _gitConfigSet(String key, String value) async {
    if (value.isEmpty) return;
    await Process.run(
      'git', ['config', '--global', key, value],
      environment: RuntimeEnvir.baseEnv,
    );
  }

  Future<void> _editField({
    required String title,
    required String current,
    required String hint,
    required TextInputType keyboard,
    required Future<void> Function(String) onSave,
  }) async {
    final ctrl = TextEditingController(text: current);
    final result = await showThemedDialog<String>(
      context: context,
      title: title,
      builder: (ctx) =>  Padding(
        padding: const EdgeInsets.all(10),
        child: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: keyboard,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(borderSide: BorderSide.none)
           //   border:  OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
      ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      
    );
    if (result == null || result == current) return;
    await onSave(result);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configuração salva'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SettingsPageScaffold(
      title: 'Git',
      canPop: false,
      onBackPressed: () => Navigator.of(context).pop(),
      onSystemBack: () => Navigator.of(context).pop(),
      child: _loading
          ? const Padding(
              padding: EdgeInsets.only(top: 80),
              child: Center(child: CircularProgressIndicator()),
            )
          : !_gitAvailable
              ? _GitNotFound(cs: cs)
              : _GitConfig(
                  name: _name,
                  email: _email,
                  branch: _branch,
                  remoteGitBuild: _remoteGitBuild,
                  githubToken: _githubToken,
                  gitConfigured: _name.isNotEmpty && _email.isNotEmpty,
                  onEditName: () => _editField(
                    title: 'Nome de usuário',
                    current: _name,
                    hint: 'Seu Nome',
                    keyboard: TextInputType.name,
                    onSave: (v) async {
                      await _gitConfigSet('user.name', v);
                      if (mounted) setState(() => _name = v);
                    },
                  ),
                  onEditEmail: () => _editField(
                    title: 'Email',
                    current: _email,
                    hint: 'voce@email.com',
                    keyboard: TextInputType.emailAddress,
                    onSave: (v) async {
                      await _gitConfigSet('user.email', v);
                      if (mounted) setState(() => _email = v);
                    },
                  ),
                  onEditBranch: () => _editField(
                    title: 'Branch padrão',
                    current: _branch,
                    hint: 'main',
                    keyboard: TextInputType.text,
                    onSave: (v) async {
                      await _gitConfigSet('init.defaultBranch', v);
                      if (mounted) setState(() => _branch = v);
                    },
                  ),
                  onEditToken: () => _editField(
                    title: 'GitHub Personal Access Token',
                    current: _githubToken,
                    hint: 'ghp_xxxxxxxxxxxxxxxxxxxx',
                    keyboard: TextInputType.visiblePassword,
                    onSave: (v) async {
                      await context.read<SettingsProvider>().setGithubToken(v);
                      if (mounted) setState(() => _githubToken = v);
                    },
                  ),
                  onToggleRemoteBuild: (v) async {
                    await context.read<SettingsProvider>().setRemoteGitBuild(v);
                    if (mounted) setState(() => _remoteGitBuild = v);
                  },
                ),
    );
  }
}

// ── Git not found ─────────────────────────────────────────────────────────────

class _GitNotFound extends StatelessWidget {
  final ColorScheme cs;
  const _GitNotFound({required this.cs});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 32),
        settingsInfoTile(
          context,
          title: 'Git não encontrado',
          subtitle: 'Instale o git via terminal: pkg install git',
          iconBg: cs.error,
          icon: FontAwesomeIcons.triangleExclamation,
          borderRadius: BorderRadius.circular(16),
        ),
      ],
    );
  }
}

// ── Git config tiles ──────────────────────────────────────────────────────────

class _GitConfig extends StatelessWidget {
  final String name;
  final String email;
  final String branch;
  final bool remoteGitBuild;
  final String githubToken;
  final bool gitConfigured;
  final VoidCallback onEditName;
  final VoidCallback onEditEmail;
  final VoidCallback onEditBranch;
  final VoidCallback onEditToken;
  final ValueChanged<bool> onToggleRemoteBuild;

  const _GitConfig({
    required this.name,
    required this.email,
    required this.branch,
    required this.remoteGitBuild,
    required this.githubToken,
    required this.gitConfigured,
    required this.onEditName,
    required this.onEditEmail,
    required this.onEditBranch,
    required this.onEditToken,
    required this.onToggleRemoteBuild,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokenMasked = githubToken.isEmpty
        ? 'Não configurado'
        : '${githubToken.substring(0, githubToken.length.clamp(0, 4))}••••••••';
    final canEnableRemote = gitConfigured && githubToken.isNotEmpty;

    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        settingsSectionHeader(context, 'Identidade'),
        settingsOptionTile(
          context,
          title: 'Nome de usuário',
          subtitle: name.isEmpty ? 'Não configurado' : name,
          onTap: onEditName,
          iconBg: Colors.indigo,
          icon: FontAwesomeIcons.userPen,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(5)),
        ),
        settingsOptionTile(
          context,
          title: 'Email',
          subtitle: email.isEmpty ? 'Não configurado' : email,
          onTap: onEditEmail,
          iconBg: Colors.teal,
          icon: FontAwesomeIcons.envelope,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(5), bottom: Radius.circular(30)),
        ),
        settingsSectionHeader(context, 'Repositório'),
        settingsOptionTile(
          context,
          title: 'Branch padrão',
          subtitle: branch,
          onTap: onEditBranch,
          iconBg: Colors.deepPurple,
          icon: FontAwesomeIcons.codeBranch,
          borderRadius: BorderRadius.circular(30),
        ),

        // ── Compilação Remota ──────────────────────────────────────────────
        settingsSectionHeader(context, 'Compilação Remota'),
        if (!gitConfigured)
          settingsInfoTile(
            context,
            title: 'Configure nome e email acima',
            subtitle: 'A compilação remota requer identidade git configurada.',
            iconBg: cs.errorContainer,
            icon: FontAwesomeIcons.circleInfo,
            borderRadius: BorderRadius.circular(30),
          ),
        settingsOptionTile(
          context,
          title: 'GitHub Personal Access Token',
          subtitle: tokenMasked,
          onTap: gitConfigured ? onEditToken : () {},
          iconBg: const Color(0xFF24292F),
          icon: FontAwesomeIcons.github,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30), bottom: Radius.circular(5)),
        ),
        settingsSwitchTile(
          context,
          title: 'Compilação Remota com Git',
          subtitle: canEnableRemote
              ? 'Faz commit + push e compila via GitHub Actions'
              : 'Configure nome, email e token para ativar',
          value: remoteGitBuild && canEnableRemote,
          onChanged: (v) => onToggleRemoteBuild(v),
          enabled: canEnableRemote,
          iconBg: remoteGitBuild && canEnableRemote
              ? Colors.green.shade700
              : cs.surfaceContainerHigh,
          icon: FontAwesomeIcons.cloudArrowUp,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(6), bottom: Radius.circular(30)),
        ),
       /*  const SizedBox(height: 8),
        if (remoteGitBuild && canEnableRemote)
          settingsInfoTile(
            context,
            title: 'Como funciona',
            subtitle:
                'Ao pressionar ▶ o projeto é commitado, enviado ao GitHub '
                'e compilado pelo GitHub Actions. Quando pronto, o APK é '
                'baixado automaticamente e o menu de instalação é aberto.',
            iconBg: cs.primaryContainer,
            icon: FontAwesomeIcons.circleInfo,
            borderRadius: BorderRadius.circular(16),
          ), */
        const SizedBox(height: 250),
      ],
    );
  }
}
