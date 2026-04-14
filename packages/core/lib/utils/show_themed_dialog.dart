// core/lib/utils/show_themed_dialog.dart
//
// Unified frosted-glass dialog helper.
//
// Dois modos:
//   • Conteúdo livre  → passe [builder]
//   • Lista picker    → passe [items], [current] e [label]
//
// Opcionalmente passe [actions] (estático) ou [actionsListenable] (dinâmico/reativo)
// para exibir botões no rodapé.

import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<T?> showThemedDialog<T>({
  required BuildContext context,

  // ── Compartilhado ─────────────────────────────────────────────────────────
  String? title,
  bool barrierDismissible = true,

  // ── Modo A: conteúdo livre ────────────────────────────────────────────────
  WidgetBuilder? builder,

  // ── Modo B: lista picker ──────────────────────────────────────────────────
  List<T>? items,
  T? current,
  String Function(T)? label,

  // ── Actions estáticas (rodapé) ────────────────────────────────────────────
  // Use para diálogos simples cujos botões não mudam após a abertura.
  // Exemplo:
  //   actions: [
  //     TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
  //     FilledButton(onPressed: () { … }, child: Text('Confirmar')),
  //   ]
  List<Widget>? actions,

  // ── Actions dinâmicas (rodapé reativo) ────────────────────────────────────
  // Use quando os botões do rodapé precisam mudar em resposta a mudanças de
  // estado interno do widget passado via [builder].
  // O widget filho é responsável por atualizar o ValueNotifier sempre que
  // seu estado mudar (ex.: após cada fase de instalação).
  // Exemplo:
  //   final notifier = ValueNotifier<List<Widget>>([]);
  //   showThemedDialog(actionsListenable: notifier, builder: (_) => MyBody(notifier: notifier));
  ValueListenable<List<Widget>>? actionsListenable,

  // ── Layout ────────────────────────────────────────────────────────────────
  double maxWidth = 320,
  double maxHeight = 480,
}) {
  assert(
    builder != null || items != null,
    'Forneça builder (conteúdo livre) ou items (lista picker).',
  );
  assert(
    actions == null || actionsListenable == null,
    'Use apenas [actions] ou [actionsListenable], não ambos.',
  );

  final isDark = Theme.of(context).brightness == Brightness.dark;
  final iconBrightness = isDark ? Brightness.light : Brightness.dark;
  final cs = Theme.of(context).colorScheme;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'ThemedDialog',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (dialogContext, animation, secondaryAnimation) {
      return AnnotatedRegion<SystemUiOverlayStyle>(
        sized: false,
        value: SystemUiOverlayStyle(
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: iconBrightness,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: iconBrightness,
          statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
        ),
        child: SizedBox.expand(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Backdrop blur + scrim ──────────────────────────────────────
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: GestureDetector(
                    onTap: barrierDismissible
                        ? () => Navigator.of(dialogContext).pop()
                        : null,
                    behavior: HitTestBehavior.opaque,
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),

              // ── Card ──────────────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () {},
                  child: Material(
                    type: MaterialType.transparency,
                    child: Container(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth,
                        maxHeight: maxHeight,
                      ),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: cs.outlineVariant,
                          width: 0.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 36,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Cabeçalho ──────────────────────────────────────
                          if (title != null) ...[
                            Padding(
                              padding:
                                  const EdgeInsets.fromLTRB(20, 18, 20, 12),
                              child: Text(
                                title,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                            Divider(height: 1, color: cs.outlineVariant),
                          ],

                          // ── Corpo ──────────────────────────────────────────
                          if (items != null)
                            _PickerBody<T>(
                              ctx: dialogContext,
                              items: items,
                              current: current,
                              label: label!,
                              cs: cs,
                            )
                          else
                            Flexible(
                              child: SingleChildScrollView(
                                child: builder!(dialogContext),
                              ),
                            ),

                          // ── Actions estáticas ──────────────────────────────
                          if (actions != null && actions.isNotEmpty)
                            _ActionsBar(actions: actions, cs: cs),

                          // ── Actions dinâmicas (reativas via ValueNotifier) ─
                          if (actionsListenable != null)
                            ValueListenableBuilder<List<Widget>>(
                              valueListenable: actionsListenable,
                              builder: (_, dynamicActions, __) {
                                if (dynamicActions.isEmpty) {
                                  return const SizedBox.shrink();
                                }
                                return _ActionsBar(
                                    actions: dynamicActions, cs: cs);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final fade = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
      );
      return FadeTransition(
        opacity: fade,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1.0).animate(fade),
          child: child,
        ),
      );
    },
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ActionsBar
//
// Rodapé com linha de botões alinhados à direita.
// Espaçamento de 8 px entre cada action.
// ─────────────────────────────────────────────────────────────────────────────

class _ActionsBar extends StatelessWidget {
  const _ActionsBar({required this.actions, required this.cs});

  final List<Widget> actions;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (int i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                actions[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PickerBody
// ─────────────────────────────────────────────────────────────────────────────

class _PickerBody<T> extends StatelessWidget {
  const _PickerBody({
    required this.ctx,
    required this.items,
    required this.current,
    required this.label,
    required this.cs,
  });

  final BuildContext ctx;
  final List<T> items;
  final T? current;
  final String Function(T) label;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        shrinkWrap: true,
        itemCount: items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          final isSelected = item == current;

          return InkWell(
            onTap: () => Navigator.of(ctx).pop(item),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label(item),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? cs.primary : cs.onSurface,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}