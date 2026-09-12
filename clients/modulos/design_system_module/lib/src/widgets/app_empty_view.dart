import 'package:flutter/material.dart';

/// Estado vazio padronizado: um icone ilustrativo, um titulo e um subtitulo
/// opcional. Complementa o [AppErrorView] (erro) e o CircularProgressIndicator
/// (carregando) para fechar o trio de estados de tela do design system.
class AppEmptyView extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;

  /// Botão do próximo passo, quando existe um.
  ///
  /// Um estado vazio que só descreve o vazio deixa a pessoa procurando o botão
  /// sozinha — e às vezes ele nem mora naquela tela. Foi o que aconteceu na
  /// lista de usuários do tenant: não há "adicionar" ali de propósito (usuário
  /// entra por convite), mas nada apontava para onde a ação acontece.
  final Widget? action;

  const AppEmptyView({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}
