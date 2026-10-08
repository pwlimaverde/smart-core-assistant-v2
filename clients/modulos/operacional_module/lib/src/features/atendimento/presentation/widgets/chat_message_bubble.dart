import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/model/midia_mensagem.dart';
import '../../domain/model/mensagem_thread.dart';
import 'midia_da_bolha.dart';

/// P1.1-D — onde a bolha cai dentro do bloco de mensagens consecutivas do
/// mesmo remetente. Decide espaçamento, cantos, rodapé e selo de IA.
enum PosicaoNoGrupo {
  /// Sozinha: nem a anterior nem a próxima são do mesmo bloco.
  unica,

  /// Abre o bloco: a próxima continua, a anterior não.
  primeira,

  /// No miolo: anterior e próxima são do mesmo bloco.
  meio,

  /// Fecha o bloco: a anterior continua, a próxima não.
  ultima;

  /// Começa um bloco — leva o espaço maior acima e o selo de IA.
  bool get abreBloco => this == unica || this == primeira;

  /// Termina um bloco — leva o espaço maior abaixo e o rodapé (hora + ticks).
  bool get fechaBloco => this == unica || this == ultima;
}

/// P1.1-D — duas mensagens são do mesmo bloco quando vêm do mesmo lado da
/// conversa (bot e atendente contam separados), no mesmo dia e com até
/// 2 minutos entre elas.
///
/// O "mesmo dia" é o que faz o separador de dia quebrar o bloco: onde ele
/// aparece, as vizinhas nunca são do mesmo bloco. A pendente local (id < 0)
/// não tem regra própria — está no fim (`ordenarParaExibir`) e agrupa com a
/// anterior pelo mesmo critério.
bool mesmoBloco(MensagemThread? a, MensagemThread? b) =>
    a != null &&
    b != null &&
    a.remetente == b.remetente &&
    DateUtils.isSameDay(a.timestamp, b.timestamp) &&
    b.timestamp.difference(a.timestamp).abs() <= const Duration(minutes: 2);

/// P1.1-D — a posição de [atual] no bloco, dadas as vizinhas na ordem em que
/// a conversa é desenhada (mais antiga primeiro). Função pura: a tela só a
/// chama no `itemBuilder`.
PosicaoNoGrupo posicaoNoGrupo(
  MensagemThread? anterior,
  MensagemThread atual,
  MensagemThread? proxima,
) {
  final continuaAnterior = mesmoBloco(anterior, atual);
  final continuaNaProxima = mesmoBloco(atual, proxima);
  return switch ((continuaAnterior, continuaNaProxima)) {
    (false, false) => PosicaoNoGrupo.unica,
    (false, true) => PosicaoNoGrupo.primeira,
    (true, true) => PosicaoNoGrupo.meio,
    (true, false) => PosicaoNoGrupo.ultima,
  };
}

/// Bolha de mensagem do chat (WS-6.3), estilo WhatsApp — usa as cores `chat*`
/// reservadas no design system. Mensagens de `atendente`/`bot` (outbound)
/// alinham à direita; `usuario` (inbound) à esquerda.
///
/// [mensagem.conteudo] é PII: este widget apenas exibe, nunca loga.
class ChatMessageBubble extends StatelessWidget {
  final MensagemThread mensagem;

  /// P2 — "responder": o menu só aparece quando a tela sabe o que fazer com
  /// ele (a conversa embutida na ficha, por exemplo, não cita).
  final VoidCallback? aoCitar;

  /// P1.1-D — posição no bloco de mensagens consecutivas. O padrão `unica`
  /// mantém a bolha completa onde não há vizinhas (ficha, testes).
  final PosicaoNoGrupo posicao;

  /// P2a — o anexo não carregou (URL assinada vencida). A tela decide
  /// recarregar a conversa; sem o callback a bolha só mostra "indisponível".
  final VoidCallback? aoMidiaExpirada;

  /// P2a — substitui o `url_launcher` do cartão de documento (testes).
  final AbrirUrlExterna? abrirUrl;

  const ChatMessageBubble({
    super.key,
    required this.mensagem,
    this.aoCitar,
    this.posicao = PosicaoNoGrupo.unica,
    this.aoMidiaExpirada,
    this.abrirUrl,
  });

  bool get _isOutbound =>
      mensagem.remetente == 'atendente' || mensagem.remetente == 'bot';

  /// P2a — numa mensagem com anexo o `conteudo` costuma ser o nome do arquivo
  /// (o que o servidor grava sem legenda); só vira texto da bolha quando é
  /// legenda de verdade.
  bool get _mostraConteudo {
    final midia = mensagem.midia;
    if (midia == null) return true;
    final texto = mensagem.conteudo.trim();
    if (texto.isEmpty || texto == midia.nomeArquivo.trim()) return false;
    // Mídia gravada antes da limpeza ainda traz o link da CDN no conteúdo.
    return !texto.startsWith('http');
  }

  bool get _temAnalise =>
      (mensagem.analiseMidia?.trim().isNotEmpty ?? false) ||
      (mensagem.resumoMidia?.trim().isNotEmpty ?? false);

  /// Canto "cheio" e canto reduzido do lado de quem falou.
  static const _raio = Radius.circular(10);
  static const _raioReduzido = Radius.circular(3);

  /// P1.1-D — no meio e no fim do bloco, o canto de cima do lado do remetente
  /// encolhe e as bolhas parecem uma pilha só.
  BorderRadius get _cantos {
    if (posicao.abreBloco) return AppRadius.card;
    return BorderRadius.only(
      topLeft: _isOutbound ? _raio : _raioReduzido,
      topRight: _isOutbound ? _raioReduzido : _raio,
      bottomLeft: _raio,
      bottomRight: _raio,
    );
  }

  /// P1.1-D — 1 px dentro do bloco; `AppSpacing.xs` nas bordas do bloco.
  EdgeInsets get _margem => EdgeInsets.only(
    top: posicao.abreBloco ? AppSpacing.xs : 1,
    bottom: posicao.fechaBloco ? AppSpacing.xs : 0,
  );

  /// P1.1-D — o tick sai do meio do bloco, como no WhatsApp Web, MENOS quando
  /// a mensagem falhou: esconder a falha atrás da vizinha faria o atendente
  /// achar que o contato recebeu.
  bool get _mostraTickSozinho =>
      !posicao.fechaBloco &&
      _isOutbound &&
      mensagem.statusEntrega == StatusEntrega.falhou;

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

    final bolha = Align(
      alignment: _isOutbound ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 380),
        margin: _margem,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(color: bg, borderRadius: _cantos),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // P1.1-D — o selo de IA abre o bloco; repetido em cada bolha
            // seguida do bot ele vira ruído.
            if (mensagem.geradoPorIa && posicao.abreBloco) ...[
              _IndicadorIa(colors: colors),
              const SizedBox(height: 4),
            ],
            if (mensagem.citacao case final citacao?) ...[
              _TrechoCitado(citacao: citacao, fg: fg),
              const SizedBox(height: 4),
            ],
            if (mensagem.midia case final midia?) ...[
              MidiaDaBolha(
                midia: midia,
                fg: fg,
                aoMidiaExpirada: aoMidiaExpirada,
                abrirUrl: abrirUrl,
              ),
              if (_mostraConteudo) const SizedBox(height: 4),
            ],
            if (_mostraConteudo)
              Text(mensagem.conteudo, style: TextStyle(color: fg)),
            // P8 — o que a mensagem interativa carrega além do título. Sem isto
            // a enquete chegava só com a pergunta e nenhuma alternativa: quem
            // lia o chat não fazia ideia do que tinha sido perguntado.
            if (_extras.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _Extras(itens: _extras, icone: _iconeDoTipo, fg: fg),
            ],
            if (_temAnalise) ...[
              const SizedBox(height: AppSpacing.xs),
              _AnaliseIa(
                tipo: mensagem.midia?.tipo,
                transcricao: mensagem.analiseMidia,
                resumo: mensagem.resumoMidia,
                colors: colors,
                fg: fg,
              ),
            ],
            // P1.1-D — hora e ticks fecham o bloco: só a última bolha diz
            // quando o bloco terminou e como ele foi entregue.
            if (posicao.fechaBloco) ...[
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat('HH:mm').format(mensagem.timestamp),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: fg.withValues(alpha: 0.7),
                    ),
                  ),
                  // Tick só no que SAIU: na mensagem do contato não há
                  // entrega a confirmar, e o ícone ali significaria outra
                  // coisa.
                  if (_isOutbound) ...[
                    const SizedBox(width: 4),
                    _Ticks(status: mensagem.statusEntrega, fg: fg),
                  ],
                ],
              ),
            ] else if (_mostraTickSozinho) ...[
              const SizedBox(height: 2),
              _Ticks(status: mensagem.statusEntrega, fg: fg),
            ],
          ],
        ),
      ),
    );

    // P8 — as reações ficam por FORA do balão, encostadas nele, como no
    // WhatsApp Web: dentro, elas competiriam com o texto da mensagem.
    final comReacoes = mensagem.reacoes.isEmpty
        ? bolha
        : Column(
            crossAxisAlignment: _isOutbound
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              bolha,
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _Reacoes(reacoes: mensagem.reacoes, bg: bg),
              ),
            ],
          );

    if (aoCitar == null) return comReacoes;
    // Clique longo é o gesto do WhatsApp para responder; no desktop o botão
    // direito chega como `onSecondaryTap`.
    return GestureDetector(
      onLongPress: aoCitar,
      onSecondaryTap: aoCitar,
      child: comReacoes,
    );
  }

  /// P8 — as linhas extras de uma mensagem interativa, na ordem em que o autor
  /// as escreveu. Vazio em tudo que não for enquete, lista ou botões.
  List<String> get _extras => switch (mensagem.tipo) {
    'enquete' => mensagem.opcoesDaEnquete,
    'lista' => mensagem.itensDaLista,
    'botoes' => mensagem.rotulosDosBotoes,
    _ => const [],
  };

  IconData get _iconeDoTipo => switch (mensagem.tipo) {
    'enquete' => Icons.radio_button_unchecked,
    'lista' => Icons.list,
    _ => Icons.crop_square,
  };
}

/// P8 — alternativas da enquete, itens da lista, rótulos dos botões.
///
/// São opções que o contato vê no celular dele; o atendente não pode clicar
/// nelas daqui. Por isso são texto com marcador, e não botões: um botão que não
/// faz nada é pior do que uma lista que se explica.
class _Extras extends StatelessWidget {
  final List<String> itens;
  final IconData icone;
  final Color fg;

  const _Extras({required this.itens, required this.icone, required this.fg});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in itens)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icone, size: 13, color: fg.withValues(alpha: 0.7)),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: fg.withValues(alpha: 0.9),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// P8 — os emojis com que reagiram a esta mensagem.
class _Reacoes extends StatelessWidget {
  final List<ReacaoDaMensagem> reacoes;
  final Color bg;

  const _Reacoes({required this.reacoes, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: context.colors.border),
      ),
      child: Text(
        // Um emoji por pessoa; repetido quando duas reagiram igual, como no
        // WhatsApp.
        reacoes.map((r) => r.emoji).join(),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }
}

/// P2 — o retângulo do trecho respondido, acima do texto da bolha.
class _TrechoCitado extends StatelessWidget {
  final CitacaoMensagem citacao;
  final Color fg;

  const _TrechoCitado({required this.citacao, required this.fg});

  @override
  Widget build(BuildContext context) {
    final quemFalou = switch (citacao.remetente) {
      'atendente' => 'Você',
      'bot' => 'Assistente',
      _ => 'Contato',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.08),
        borderRadius: AppRadius.card,
        border: Border(
          left: BorderSide(color: fg.withValues(alpha: 0.5), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            quemFalou,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg.withValues(alpha: 0.9),
              fontWeight: FontWeight.w600,
            ),
          ),
          // O trecho é PII, como qualquer conteúdo de mensagem: exibe, não loga.
          Text(
            citacao.preview,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: fg.withValues(alpha: 0.75)),
          ),
        ],
      ),
    );
  }
}

/// P2 — os ticks de entrega/leitura, com o mesmo vocabulário do WhatsApp.
class _Ticks extends StatelessWidget {
  final StatusEntrega status;
  final Color fg;

  const _Ticks({required this.status, required this.fg});

  @override
  Widget build(BuildContext context) {
    final (icone, cor, rotulo) = switch (status) {
      StatusEntrega.pendente => (
        Icons.schedule,
        fg.withValues(alpha: 0.6),
        'Na fila de envio',
      ),
      StatusEntrega.enviada => (
        Icons.done,
        fg.withValues(alpha: 0.7),
        'Enviada',
      ),
      StatusEntrega.entregue => (
        Icons.done_all,
        fg.withValues(alpha: 0.7),
        'Entregue',
      ),
      // Azul é a única cor com significado aqui: é o que distingue "chegou" de
      // "leram" num relance.
      StatusEntrega.lida => (Icons.done_all, AppPalette.info, 'Lida'),
      StatusEntrega.falhou => (
        Icons.error_outline,
        AppPalette.danger,
        'Falhou no envio',
      ),
    };
    return Tooltip(
      message: rotulo,
      child: Icon(icone, size: 14, color: cor),
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
/// Seção da análise IA: rótulo e texto já limpos.
typedef SecaoAnaliseIa = ({String rotulo, String texto});

/// Áudio mostra a transcrição e, se houver, o resumo; as demais mídias mostram
/// só a descrição (o `resumo_midia` da imagem). Vazio não vira seção.
List<SecaoAnaliseIa> secoesDaAnaliseIa({
  required TipoMidia? tipo,
  required String? transcricao,
  required String? resumo,
}) {
  final texto = transcricao?.trim() ?? '';
  final descricao = resumo?.trim() ?? '';
  final ehAudio = tipo == TipoMidia.audio;
  return [
    if (ehAudio && texto.isNotEmpty) (rotulo: 'Transcrição', texto: texto),
    if (descricao.isNotEmpty)
      (rotulo: ehAudio ? 'Resumo' : 'Descrição', texto: descricao),
  ];
}

class _AnaliseIa extends StatefulWidget {
  final TipoMidia? tipo;
  final String? transcricao;
  final String? resumo;
  final AppColors colors;
  final Color fg;

  const _AnaliseIa({
    required this.tipo,
    required this.transcricao,
    required this.resumo,
    required this.colors,
    required this.fg,
  });

  @override
  State<_AnaliseIa> createState() => _AnaliseIaState();
}

class _AnaliseIaState extends State<_AnaliseIa> {
  bool _aberto = false;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final fg = widget.fg;
    final secoes = secoesDaAnaliseIa(
      tipo: widget.tipo,
      transcricao: widget.transcricao,
      resumo: widget.resumo,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.06),
        borderRadius: AppRadius.sm,
        border: Border(left: BorderSide(color: widget.colors.accent, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => setState(() => _aberto = !_aberto),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 12,
                  color: fg.withValues(alpha: 0.7),
                ),
                const SizedBox(width: 4),
                Text(
                  'Análise IA',
                  style: textTheme.labelSmall?.copyWith(
                    color: fg.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(
                  _aberto ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: fg.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
          if (_aberto)
            for (final secao in secoes)
              _secao(secao.rotulo, secao.texto, textTheme),
        ],
      ),
    );
  }

  Widget _secao(String rotulo, String texto, TextTheme textTheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: textTheme.labelSmall?.copyWith(
              color: widget.fg.withValues(alpha: 0.7),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            texto,
            style: textTheme.bodySmall?.copyWith(
              color: widget.fg.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}
