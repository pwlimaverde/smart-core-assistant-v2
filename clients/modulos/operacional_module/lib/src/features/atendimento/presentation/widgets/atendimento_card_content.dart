import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/model/atendimento_resumo.dart';
import 'avatar_do_contato.dart';

/// Conteúdo do cartão de atendimento no quadro — o `ws-card` do workspace.
///
/// Três faixas, como no desenho: quem é (avatar, nome, telefone e há quanto
/// tempo falou), o que foi dito por último, e os sinais do atendimento
/// (prioridade, revisão pendente, sentimento, atendente e não lidas). O
/// cartão antigo mostrava só o assunto; para decidir qual conversa abrir, o
/// que importa é quem escreveu e o quê.
class AtendimentoCardContent extends StatelessWidget {
  final AtendimentoResumo atendimento;

  const AtendimentoCardContent({super.key, required this.atendimento});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final a = atendimento;
    final previa = previaDaUltimaMensagem(a);
    final quando = a.dataUltimaMensagem;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AvatarDoContato(
              nome: a.nomeParaExibir,
              fotoUrl: a.contatoFotoUrl,
              raio: 15,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    a.nomeParaExibir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                      color: colors.fgStrong,
                    ),
                  ),
                  // Sem nome, o telefone já é o título: repetir seria ruído.
                  if (a.contatoNome.isNotEmpty && a.contatoTelefone.isNotEmpty)
                    Text(
                      a.contatoTelefone,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        height: 1.25,
                        color: colors.fgMuted,
                      ),
                    ),
                ],
              ),
            ),
            if (quando != null) ...[
              const SizedBox(width: 6),
              Text(
                tempoRelativo(quando),
                style: TextStyle(fontSize: 10, color: colors.fgMuted),
              ),
            ],
          ],
        ),
        if (previa.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            previa,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.4,
              color: colors.fgMuted,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TagDePrioridade(prioridade: a.prioridade),
                  // P16 — a IA respondeu com pouca confiança e ninguém
                  // conferiu.
                  if (a.revisaoPendente)
                    Tooltip(
                      message:
                          'A IA respondeu com pouca confiança. Confira a resposta.',
                      child: TagDoWorkspace(
                        rotulo: 'Revisar',
                        icone: Icons.rate_review_outlined,
                        cor: colors.warning,
                        fundo: colors.warningSoft,
                      ),
                    ),
                  if (a.sentimentoLabel case final label? when label.isNotEmpty)
                    _TagDeSentimento(label: label),
                  _Atendente(nome: a.atendenteNome),
                ],
              ),
            ),
            if (a.naoLidas > 0) ...[
              const SizedBox(width: 6),
              BadgeDeNaoLidas(quantidade: a.naoLidas),
            ],
          ],
        ),
      ],
    );
  }
}

/// O que o cartão mostra da última mensagem.
///
/// Mídia sem legenda vira o nome do que foi mandado; o que saiu daqui (do bot
/// ou de um atendente) ganha a seta, como no desenho — quem olha a fila quer
/// saber de relance se a última palavra foi do cliente. Sem mensagem nenhuma
/// (servidor antigo, conversa aberta pela equipe), fica o assunto.
String previaDaUltimaMensagem(AtendimentoResumo a) {
  var texto = a.ultimaMensagem.trim();
  if (texto.isEmpty) texto = _rotuloDoTipo(a.ultimaMensagemTipo);
  if (texto.isEmpty) return a.assunto;
  final saiuDaqui =
      a.ultimaMensagemRemetente.isNotEmpty &&
      a.ultimaMensagemRemetente != 'contato';
  return saiuDaqui ? '↳ $texto' : texto;
}

String _rotuloDoTipo(String tipo) {
  final t = tipo.toLowerCase();
  if (t.contains('image') || t.contains('sticker')) return '📷 Imagem';
  if (t.contains('audio') || t.contains('ptt')) return '🎤 Áudio';
  if (t.contains('video')) return '🎬 Vídeo';
  if (t.contains('document')) return '📄 Documento';
  if (t.contains('location')) return '📍 Localização';
  if (t.contains('contact')) return '👤 Contato';
  return '';
}

/// "agora", "12 min", a hora de hoje, "ontem" ou a data — o `ws-card__when`.
String tempoRelativo(DateTime quando, {DateTime? agora}) {
  final ref = agora ?? DateTime.now();
  final diferenca = ref.difference(quando);
  if (diferenca.inMinutes < 1) return 'agora';
  if (diferenca.inMinutes < 60) return '${diferenca.inMinutes} min';
  bool mesmoDia(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  if (mesmoDia(quando, ref)) return DateFormat('HH:mm').format(quando);
  if (mesmoDia(quando, ref.subtract(const Duration(days: 1)))) return 'ontem';
  return DateFormat('dd/MM').format(quando);
}

/// A etiqueta miúda do workspace (`ws-tag`).
class TagDoWorkspace extends StatelessWidget {
  final String rotulo;
  final Color cor;
  final Color fundo;
  final IconData? icone;

  const TagDoWorkspace({
    super.key,
    required this.rotulo,
    required this.cor,
    required this.fundo,
    this.icone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(color: fundo, borderRadius: AppRadius.sm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icone != null) ...[
            Icon(icone, size: 10, color: cor),
            const SizedBox(width: 4),
          ],
          Text(
            rotulo,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Prioridade com as cores do desenho: normal azul, baixa verde, alta laranja
/// e urgente dourado.
class TagDePrioridade extends StatelessWidget {
  final String prioridade;

  const TagDePrioridade({super.key, required this.prioridade});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final valor = prioridade.isEmpty ? 'normal' : prioridade.toLowerCase();
    final (cor, fundo) = switch (valor) {
      'baixa' => (colors.success, colors.successSoft),
      'alta' => (colors.warning, colors.warningSoft),
      'urgente' => (colors.accentHover, colors.accentSoft),
      _ => (colors.info, colors.infoSoft),
    };
    return TagDoWorkspace(rotulo: valor, cor: cor, fundo: fundo);
  }
}

class _TagDeSentimento extends StatelessWidget {
  final String label;

  const _TagDeSentimento({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (cor, fundo) = switch (label.toLowerCase()) {
      'positivo' => (colors.success, colors.successSoft),
      'negativo' => (colors.danger, colors.dangerSoft),
      _ => (colors.fgMuted, colors.chip),
    };
    return TagDoWorkspace(rotulo: label, cor: cor, fundo: fundo);
  }
}

/// Quem está com a conversa: mini-avatar e nome, ou "Sem atendente".
class _Atendente extends StatelessWidget {
  final String nome;

  const _Atendente({required this.nome});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    if (nome.isEmpty) {
      return Text(
        'Sem atendente',
        style: TextStyle(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: colors.fgSubtle,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accent,
            shape: BoxShape.circle,
          ),
          child: Text(
            AvatarDoContato.iniciais(nome),
            style: const TextStyle(
              fontSize: 7,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 110),
          child: Text(
            nome,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 10, color: colors.fgMuted),
          ),
        ),
      ],
    );
  }
}

/// B6 (N9 E4) — quantas mensagens do contato ninguém leu ainda: o selo verde
/// do WhatsApp (`ws-card__unread`).
class BadgeDeNaoLidas extends StatelessWidget {
  final int quantidade;

  /// Na trilha do modo Atendimento o selo é vermelho e menor, sobre o avatar.
  final bool compacto;

  const BadgeDeNaoLidas({
    super.key,
    required this.quantidade,
    this.compacto = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final rotulo = quantidade > 99 ? '99+' : '$quantidade';
    return Semantics(
      label: '$quantidade mensagens não lidas',
      excludeSemantics: true,
      child: Container(
        key: const ValueKey('nao-lidas'),
        constraints: BoxConstraints(minWidth: compacto ? 16 : 18),
        height: compacto ? 16 : 18,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: compacto ? colors.danger : colors.success,
          borderRadius: AppRadius.pill,
          border: compacto ? Border.all(color: colors.bg, width: 2) : null,
        ),
        child: Text(
          rotulo,
          style: TextStyle(
            fontSize: compacto ? 9 : 10,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
