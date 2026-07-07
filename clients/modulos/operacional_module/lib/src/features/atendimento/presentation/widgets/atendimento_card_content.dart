import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

import '../../domain/model/atendimento_resumo.dart';

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
        Text(
          assunto,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: colors.fgStrong),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            _PrioridadeChip(prioridade: atendimento.prioridade),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                'Contato #${atendimento.contatoId}',
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
      decoration: BoxDecoration(
        color: corSuave,
        borderRadius: AppRadius.sm,
      ),
      child: Text(
        prioridade.isEmpty ? 'normal' : prioridade,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: cor),
      ),
    );
  }
}
