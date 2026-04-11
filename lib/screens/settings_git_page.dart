import 'dart:io';

import 'package:core/core.dart' show RuntimeEnvir;
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

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

  @override
  void initState() {
    super.initState();
    _loadConfig();
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
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Colors.grey, width: 0.2),
          borderRadius: BorderRadius.circular(30),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: keyboard,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          settingsInfoTile(
            context,
            title: 'Git não encontrado',
            subtitle: 'Instale o git via terminal: pkg install git',
            iconBg: cs.error,
            icon: FontAwesomeIcons.triangleExclamation,
            borderRadius: BorderRadius.circular(16),
          ),
        ],
      ),
    );
  }
}

// ── Git config tiles ──────────────────────────────────────────────────────────

class _GitConfig extends StatelessWidget {
  final String name;
  final String email;
  final String branch;
  final VoidCallback onEditName;
  final VoidCallback onEditEmail;
  final VoidCallback onEditBranch;

  const _GitConfig({
    required this.name,
    required this.email,
    required this.branch,
    required this.onEditName,
    required this.onEditEmail,
    required this.onEditBranch,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        settingsSectionHeader(context, 'Identidade'),
        settingsOptionTile(
          context,
          title: 'Nome de usuário',
          subtitle: name.isEmpty ? 'Não configurado' : name,
          onTap: onEditName,
          iconBg: Colors.indigo,
          icon: FontAwesomeIcons.userPen,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16), bottom: Radius.circular(4)),
        ),
        settingsOptionTile(
          context,
          title: 'Email',
          subtitle: email.isEmpty ? 'Não configurado' : email,
          onTap: onEditEmail,
          iconBg: Colors.teal,
          icon: FontAwesomeIcons.envelope,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4), bottom: Radius.circular(16)),
        ),
        settingsSectionHeader(context, 'Repositório'),
        settingsOptionTile(
          context,
          title: 'Branch padrão',
          subtitle: branch,
          onTap: onEditBranch,
          iconBg: Colors.deepPurple,
          icon: FontAwesomeIcons.codeBranch,
          borderRadius: BorderRadius.circular(16),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
