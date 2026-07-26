import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

import '../controllers/chat_state.dart';

/// Indicador visual do estado da conexão realtime do chat (WS-6.3): some
/// quando conectado, aparece com cor/ícone conforme reconectando/caído.
class ChatConnectionBadge extends StatelessWidget {
  final ChatConnectionStatus status;

  const ChatConnectionBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    if (status == ChatConnectionStatus.conectado) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final (texto, cor, corSuave, icone) = switch (status) {
      ChatConnectionStatus.conectando => (
        'Conectando…',
        colors.info,
        colors.infoSoft,
        Icons.sync,
      ),
      ChatConnectionStatus.reconectando => (
        'Conexão perdida — reconectando…',
        colors.warning,
        colors.warningSoft,
        Icons.sync_problem,
      ),
      ChatConnectionStatus.caido => (
        'Sem conexão em tempo real.',
        colors.danger,
        colors.dangerSoft,
        Icons.cloud_off,
      ),
      ChatConnectionStatus.conectado => (
        '',
        colors.success,
        colors.successSoft,
        Icons.check_circle,
      ),
    };

    return Container(
      width: double.infinity,
      color: corSuave,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(icone, size: 16, color: cor),
          const SizedBox(width: AppSpacing.xs),
          Text(
            texto,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor),
          ),
        ],
      ),
    );
  }
}
