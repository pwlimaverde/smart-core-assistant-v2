import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

import '../../domain/model/atendimento_resumo.dart';
import 'avatar_do_contato.dart';

/// Como o quadro divide a tela com a conversa — os três modos de foco do
/// workspace da v1.
enum ModoDeFoco {
  /// Só o quadro; a conversa aberta vira a mini-barra flutuante.
  quadro('Kanban', Icons.view_kanban_outlined),

  /// Quadro e conversa lado a lado.
  dividido('Dividido', Icons.vertical_split_outlined),

  /// A conversa ocupa a tela; os detalhes ficam ao lado dela.
  conversa('Atendimento', Icons.forum_outlined);

  final String rotulo;
  final IconData icone;

  const ModoDeFoco(this.rotulo, this.icone);
}

/// A conversa minimizada: mantém à vista com quem se está falando sem ocupar a
/// lateral do quadro. É o `chat_mini_bar` do workspace da v1.
class MiniBarraDaConversa extends StatelessWidget {
  /// O resumo do cartão, quando ele está no quadro filtrado. Pode faltar (a
  /// conversa foi aberta por aviso e o filtro a esconde): aí mostra o número.
  final AtendimentoResumo? atendimento;
  final int atendimentoId;
  final VoidCallback aoAbrir;
  final VoidCallback aoVerDetalhes;
  final VoidCallback aoFechar;

  const MiniBarraDaConversa({
    required this.atendimentoId,
    required this.aoAbrir,
    required this.aoVerDetalhes,
    required this.aoFechar,
    this.atendimento,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final resumo = atendimento;
    final nome = resumo?.nomeParaExibir ?? 'Atendimento #$atendimentoId';
    final linhaDeBaixo = [
      if (resumo != null && resumo.contatoTelefone.isNotEmpty)
        resumo.contatoTelefone,
      if (resumo != null && resumo.naoLidas > 0)
        '${resumo.naoLidas} não lida(s)',
    ].join(' · ');

    return Material(
      elevation: 12,
      borderRadius: BorderRadius.circular(14),
      color: colors.panel,
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
              onTap: aoAbrir,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    AvatarDoContato(
                      nome: nome,
                      fotoUrl: resumo?.contatoFotoUrl ?? '',
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            nome,
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (linhaDeBaixo.isNotEmpty)
                            Text(
                              linhaDeBaixo,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: colors.fgMuted),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Fechar a conversa',
                      onPressed: aoFechar,
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Abrir conversa'),
                      onPressed: aoAbrir,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  IconButton.outlined(
                    icon: const Icon(Icons.info_outline, size: 18),
                    tooltip: 'Detalhes do atendimento',
                    onPressed: aoVerDetalhes,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
