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
            if (mensagem.geradoPorIa) ...[
              _IndicadorIa(colors: colors),
              const SizedBox(height: 4),
            ],
            Text(mensagem.conteudo, style: TextStyle(color: fg)),
            if (mensagem.resumoMidia case final resumo?) ...[
              const SizedBox(height: AppSpacing.xs),
              _ResumoMidia(resumo: resumo, colors: colors, fg: fg),
            ],
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

/// Chip discreto "Gerado por IA" (acento gold do design system), exibido no
/// topo da bolha quando a resposta veio do bot com IA (RAG).
class _IndicadorIa extends StatelessWidget {
  final AppColors colors;

  const _IndicadorIa({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accentSoft,
        borderRadius: AppRadius.pill,
        border: Border.all(color: colors.accentRing),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_awesome, size: 12, color: colors.accent),
          const SizedBox(width: 4),
          Text(
            'Gerado por IA',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bloco secundário com o resumo/análise da mídia (áudio/imagem/documento),
/// visualmente destacado do texto principal da mensagem.
class _ResumoMidia extends StatelessWidget {
  final String resumo;
  final AppColors colors;
  final Color fg;

  const _ResumoMidia({
    required this.resumo,
    required this.colors,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: AppRadius.sm,
        border: Border(
          left: BorderSide(color: colors.accent, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.summarize_outlined,
                size: 12,
                color: fg.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                'Resumo da mídia',
                style: textTheme.labelSmall?.copyWith(
                  color: fg.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            resumo,
            style: textTheme.bodySmall?.copyWith(
              color: fg.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
