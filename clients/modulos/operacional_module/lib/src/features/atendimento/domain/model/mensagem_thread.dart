import 'package:meta/meta.dart';

import 'midia_mensagem.dart';

/// Estado de entrega de uma mensagem que o atendente enviou (N9/E7).
///
/// Existe como enum, e não como string solta, porque a bolha desenha um ícone
/// diferente para cada um e a ordem importa: `lida` implica `entregue`, que
/// implica `enviada`. Comparar strings espalharia essa ordem pela UI.
enum StatusEntrega {
  /// Ainda no outbox — o worker não a enviou ao provedor.
  pendente,

  /// Aceita pelo provedor.
  enviada,

  /// Chegou ao aparelho do contato.
  entregue,

  /// O contato abriu a conversa.
  lida,

  /// O provedor recusou. É o único estado que pede ação do atendente.
  falhou;

  /// Deriva o estado a partir do `status_envio` e dos carimbos de tempo.
  ///
  /// Os carimbos mandam sobre o status: `data_lida` preenchida com
  /// `status_envio='sent'` acontece de verdade (o webhook de leitura chega
  /// depois, e nem sempre reescreve o status).
  static StatusEntrega derivar({
    required String statusEnvio,
    DateTime? entregueEm,
    DateTime? lidaEm,
  }) {
    if (lidaEm != null) return StatusEntrega.lida;
    if (entregueEm != null) return StatusEntrega.entregue;
    return switch (statusEnvio) {
      'sent' => StatusEntrega.enviada,
      'delivered' => StatusEntrega.entregue,
      'read' => StatusEntrega.lida,
      'failed' => StatusEntrega.falhou,
      _ => StatusEntrega.pendente,
    };
  }
}

/// A mensagem que esta bolha responde (N9/E6).
///
/// Só o suficiente para desenhar o retângulo citado acima do texto: quem falou e
/// um trecho. O conteúdo íntegro já está na thread — duplicá-lo aqui inflaria
/// cada mensagem de uma conversa longa.
@immutable
final class CitacaoMensagem {
  final int mensagemId;
  final String remetente;

  /// Trecho do conteúdo citado. É PII, como todo conteúdo de mensagem.
  final String preview;

  const CitacaoMensagem({
    required this.mensagemId,
    required this.remetente,
    required this.preview,
  });
}

/// Mensagem de um thread de atendimento (chat lateral — WS-6.3).
///
/// [conteudo] é PII (mensagem do usuário/atendente): a UI nunca deve logá-lo.
@immutable
final class MensagemThread {
  final int id;
  final int atendimentoId;
  final String tipo;
  final String conteudo;
  final String remetente;
  final DateTime timestamp;
  final String statusEnvio;

  /// `true` quando a mensagem foi respondida pelo bot com IA (RAG). Opcional:
  /// mensagens antigas/sem esse dado do backend chegam com `false`.
  final bool geradoPorIa;

  /// Resumo/análise da mídia (áudio/imagem/documento) associada à mensagem,
  /// quando o backend produziu um. `null` quando não há mídia analisada.
  final String? resumoMidia;

  /// Anexo da mensagem (N9/E2). `null` em mensagem de texto puro — e também
  /// quando a mídia existiu mas já foi purgada pela retenção: nesse caso o
  /// servidor omite o bloco em vez de mandar um player que não toca nada.
  final MidiaMensagem? midia;

  /// Quando o provedor confirmou a entrega ao aparelho do contato.
  final DateTime? entregueEm;

  /// Quando o contato abriu a conversa.
  final DateTime? lidaEm;

  /// A mensagem que esta responde, quando é uma citação.
  final CitacaoMensagem? citacao;

  const MensagemThread({
    required this.id,
    required this.atendimentoId,
    required this.tipo,
    required this.conteudo,
    required this.remetente,
    required this.timestamp,
    required this.statusEnvio,
    this.geradoPorIa = false,
    this.resumoMidia,
    this.midia,
    this.entregueEm,
    this.lidaEm,
    this.citacao,
  });

  /// Estado de entrega para desenhar os ticks. Só faz sentido em mensagem que
  /// SAIU (atendente ou bot); na mensagem do contato a UI não mostra tick.
  StatusEntrega get statusEntrega => StatusEntrega.derivar(
    statusEnvio: statusEnvio,
    entregueEm: entregueEm,
    lidaEm: lidaEm,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MensagemThread && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
