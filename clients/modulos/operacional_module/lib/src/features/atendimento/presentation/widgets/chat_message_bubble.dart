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

  /// P2 — "responder": o menu só aparece quando a tela sabe o que fazer com
  /// ele (a conversa embutida na ficha, por exemplo, não cita).
  final VoidCallback? aoCitar;

  const ChatMessageBubble({super.key, required this.mensagem, this.aoCitar});

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

    final bolha = Align(
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
            if (mensagem.citacao case final citacao?) ...[
              _TrechoCitado(citacao: citacao, fg: fg),
              const SizedBox(height: 4),
            ],
            Text(mensagem.conteudo, style: TextStyle(color: fg)),
            // P8 — o que a mensagem interativa carrega além do título. Sem isto
            // a enquete chegava só com a pergunta e nenhuma alternativa: quem
            // lia o chat não fazia ideia do que tinha sido perguntado.
            if (_extras.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              _Extras(itens: _extras, icone: _iconeDoTipo, fg: fg),
            ],
            if (mensagem.resumoMidia case final resumo?) ...[
              const SizedBox(height: AppSpacing.xs),
              _ResumoMidia(resumo: resumo, colors: colors, fg: fg),
            ],
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
                // Tick só no que SAIU: na mensagem do contato não há entrega
                // a confirmar, e o ícone ali significaria outra coisa.
                if (_isOutbound) ...[
                  const SizedBox(width: 4),
                  _Ticks(status: mensagem.statusEntrega, fg: fg),
                ],
              ],
            ),
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
        border: Border(left: BorderSide(color: fg.withValues(alpha: 0.5), width: 3)),
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg.withValues(alpha: 0.75),
            ),
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
        border: Border(left: BorderSide(color: colors.accent, width: 3)),
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
