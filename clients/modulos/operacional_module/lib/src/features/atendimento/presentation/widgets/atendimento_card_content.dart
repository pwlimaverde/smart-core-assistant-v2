import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

import '../../domain/model/atendimento_resumo.dart';
import 'avatar_do_contato.dart';

/// Conteúdo textual de um card de atendimento no Kanban (WS-6.2): assunto,
/// prioridade e id do contato. Nunca exibe telefone completo (mascarado pelo
/// backend antes de chegar aqui — a UI só formata o que recebe).
class AtendimentoCardContent extends StatelessWidget {
  final AtendimentoResumo atendimento;

  const AtendimentoCardContent({super.key, required this.atendimento});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final assunto = atendimento.assunto.isEmpty
        ? 'Atendimento #${atendimento.id}'
        : atendimento.assunto;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                assunto,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.fgStrong),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (atendimento.naoLidas > 0) ...[
              const SizedBox(width: AppSpacing.xs),
              _NaoLidas(quantidade: atendimento.naoLidas),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            _PrioridadeChip(prioridade: atendimento.prioridade),
            // P16 — a IA respondeu com pouca confiança e ninguém conferiu.
            if (atendimento.revisaoPendente) ...[
              const SizedBox(width: AppSpacing.xs),
              Tooltip(
                message: 'A IA respondeu com pouca confiança. Confira a resposta.',
                child: Icon(
                  Icons.rate_review_outlined,
                  size: 14,
                  color: colors.warning,
                ),
              ),
            ],
            if (atendimento.sentimentoLabel case final label?
                when label.isNotEmpty) ...[
              const SizedBox(width: AppSpacing.xs),
              _SentimentoChip(label: label),
            ],
            const SizedBox(width: AppSpacing.xs),
            // P13 — quem é, e não `Contato #id`.
            AvatarDoContato(
              nome: atendimento.nomeParaExibir,
              fotoUrl: atendimento.contatoFotoUrl,
              raio: 9,
            ),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                atendimento.nomeParaExibir,
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: colors.fgMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// B6 (N9 E4) — quantas mensagens do contato ninguém leu ainda.
class _NaoLidas extends StatelessWidget {
  final int quantidade;

  const _NaoLidas({required this.quantidade});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rotulo = quantidade > 99 ? '99+' : '$quantidade';
    return Semantics(
      label: '$quantidade mensagens não lidas',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('nao-lidas'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        decoration: BoxDecoration(
          color: colors.danger,
          borderRadius: AppRadius.sm,
        ),
        child: Text(
          rotulo,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onError,
          ),
        ),
      ),
    );
  }
}

class _PrioridadeChip extends StatelessWidget {
  final String prioridade;

  const _PrioridadeChip({required this.prioridade});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (cor, corSuave) = switch (prioridade) {
      'alta' || 'urgente' => (colors.danger, colors.dangerSoft),
      'media' || 'média' => (colors.warning, colors.warningSoft),
      _ => (colors.info, colors.infoSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(color: corSuave, borderRadius: AppRadius.sm),
      child: Text(
        prioridade.isEmpty ? 'normal' : prioridade,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor),
      ),
    );
  }
}

/// Indicador mínimo de sentimento (N6.5): rótulo textual com cor por tom —
/// sem dashboard novo, só um sinal visual rápido na fila/Kanban.
class _SentimentoChip extends StatelessWidget {
  final String label;

  const _SentimentoChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final normalizado = label.toLowerCase();
    final (cor, corSuave) = switch (normalizado) {
      'positivo' => (colors.success, colors.successSoft),
      'negativo' => (colors.danger, colors.dangerSoft),
      _ => (colors.fgMuted, colors.infoSoft),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(color: corSuave, borderRadius: AppRadius.sm),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor),
      ),
    );
  }
}
