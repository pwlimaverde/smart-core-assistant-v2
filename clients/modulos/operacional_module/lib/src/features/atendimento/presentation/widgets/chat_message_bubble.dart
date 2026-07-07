import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/model/mensagem_thread.dart';

/// Bolha de mensagem do chat (WS-6.3), estilo WhatsApp — usa as cores `chat*`
/// reservadas no design system. Mensagens de `atendente`/`bot` (outbound)
/// alinham à direita; `usuario` (inbound) à esquerda.
///
/// [mensagem.conteudo] é PII: este widget apenas exibe, nunca loga.
class ChatMessageBubble extends StatelessWidget {
  final MensagemThread mensagem;

  const ChatMessageBubble({super.key, required this.mensagem});

  bool get _isOutbound =>
      mensagem.remetente == 'atendente' || mensagem.remetente == 'bot';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = _isOutbound
        ? (isDark ? AppPalette.chatBubOutDark : AppPalette.chatBubOutLight)
        : (isDark ? AppPalette.chatBubInDark : AppPalette.chatBubInLight);
    final fg = _isOutbound && isDark
        ? AppPalette.chatBubOutFgDark
        : (_isOutbound ? AppPalette.chatBubOutFgLight : colors.fgStrong);

    return Align(
      alignment: _isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: AppRadius.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(mensagem.conteudo, style: TextStyle(color: fg)),
            const SizedBox(height: 2),
            Text(
              DateFormat('HH:mm').format(mensagem.timestamp),
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: fg.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
