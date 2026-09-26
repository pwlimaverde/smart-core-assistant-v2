import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';

import '../../domain/model/atendimento_resumo.dart';
import 'atendimento_card_content.dart';
import 'avatar_do_contato.dart';

/// Como o quadro divide a tela com a conversa — os três modos de foco do
/// workspace da v1.
enum ModoDeFoco {
  /// Só o quadro; a conversa aberta vira a mini-barra flutuante.
  quadro('Kanban', Icons.view_kanban_outlined),

  /// Quadro e conversa lado a lado.
  dividido('Dividido', Icons.vertical_split_outlined),

  /// A conversa ocupa a tela; o quadro vira a trilha de avatares.
  conversa('Atendimento', Icons.forum_outlined);

  final String rotulo;
  final IconData icone;

  const ModoDeFoco(this.rotulo, this.icone);
}

/// A conversa minimizada: mantém à vista com quem se está falando sem ocupar a
/// lateral do quadro. É o `chat_mini_bar` (`ws-mini`) do workspace.
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
    final previa = resumo == null ? '' : previaDaUltimaMensagem(resumo);
    final quando = resumo?.dataUltimaMensagem;

    return Material(
      elevation: 16,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: colors.card,
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // O cabeçalho dourado (`ws-mini__head`): clicar devolve a conversa.
            Material(
              color: colors.accent,
              child: InkWell(
                onTap: aoAbrir,
                hoverColor: colors.accentHover,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: AvatarDoContato(
                          nome: nome,
                          fotoUrl: resumo?.contatoFotoUrl ?? '',
                          raio: 14,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              nome,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            if (linhaDeBaixo.isNotEmpty)
                              Text(
                                linhaDeBaixo,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.85),
                                ),
                              ),
                          ],
                        ),
                      ),
                      _BotaoDoCabecalho(
                        icone: Icons.info_outline,
                        dica: 'Detalhes do atendimento',
                        aoTocar: aoVerDetalhes,
                      ),
                      const SizedBox(width: 4),
                      _BotaoDoCabecalho(
                        icone: Icons.close,
                        dica: 'Fechar a conversa',
                        aoTocar: aoFechar,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (previa.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: colors.border)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: colors.chip,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color: colors.accentHover,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            previa,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: colors.fg,
                            ),
                          ),
                          if (quando != null)
                            Text(
                              tempoRelativo(quando),
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.fgMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.border)),
              ),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.success,
                  foregroundColor: Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.md,
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline, size: 15),
                label: const Text('Abrir conversa'),
                onPressed: aoAbrir,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Botão translúcido do cabeçalho dourado (`ws-mini__btn`).
class _BotaoDoCabecalho extends StatelessWidget {
  final IconData icone;
  final String dica;
  final VoidCallback aoTocar;

  const _BotaoDoCabecalho({
    required this.icone,
    required this.dica,
    required this.aoTocar,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icone, size: 16, color: Colors.white),
      tooltip: dica,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withValues(alpha: 0.15),
        minimumSize: const Size(28, 28),
        fixedSize: const Size(28, 28),
        padding: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.sm),
      ),
      onPressed: aoTocar,
    );
  }
}
