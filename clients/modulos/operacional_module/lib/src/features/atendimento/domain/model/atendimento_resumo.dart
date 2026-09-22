import 'package:meta/meta.dart';

/// Resumo de um atendimento exibido na fila/Kanban (WS-6.2).
///
/// Campos opcionais chegam como `0`/vazio na borda quando ausentes (convenção
/// do contrato protobuf) — o datasource normaliza para `null` aqui.
@immutable
final class AtendimentoResumo {
  final int id;
  final int contatoId;
  final String status;
  final int? departamentoId;
  final int? fluxoAtendimentoId;
  final int? etapaAtualId;
  final String assunto;
  final String prioridade;
  final int? atendenteHumanoId;
  final DateTime dataInicio;
  final DateTime? dataUltimaMensagem;

  /// Última leitura de sentimento da IA (N6.5); `null` enquanto não avaliado.
  final int? sentimentoNota;
  final String? sentimentoLabel;

  /// B6 (N9 E4) — mensagens do contato ainda não lidas. É o que diz, no
  /// quadro, o que falta responder.
  final int naoLidas;

  /// P13 — o contato do cartão. Vazios quando o servidor não os mandou (índice
  /// local sem rede, servidor antigo): a tela cai para `Contato #id`.
  final String contatoNome;
  final String contatoTelefone;
  final String contatoFotoUrl;

  /// Como o cartão chama o contato: o nome, senão o telefone, senão o id.
  String get nomeParaExibir => contatoNome.isNotEmpty
      ? contatoNome
      : contatoTelefone.isNotEmpty
      ? contatoTelefone
      : 'Contato #$contatoId';

  const AtendimentoResumo({
    required this.id,
    required this.contatoId,
    required this.status,
    this.departamentoId,
    this.fluxoAtendimentoId,
    this.etapaAtualId,
    required this.assunto,
    required this.prioridade,
    this.atendenteHumanoId,
    required this.dataInicio,
    this.dataUltimaMensagem,
    this.sentimentoNota,
    this.sentimentoLabel,
    this.naoLidas = 0,
    this.contatoNome = '',
    this.contatoTelefone = '',
    this.contatoFotoUrl = '',
  });

  /// Cópia com a etapa (e opcionalmente o status) alterados — usada para
  /// aplicar otimisticamente o resultado de um drag-and-drop no Kanban antes
  /// da confirmação do servidor (revertida no erro).
  AtendimentoResumo copyWith({
    int? etapaAtualId,
    String? status,
    int? naoLidas,
  }) => AtendimentoResumo(
    id: id,
    contatoId: contatoId,
    status: status ?? this.status,
    departamentoId: departamentoId,
    fluxoAtendimentoId: fluxoAtendimentoId,
    etapaAtualId: etapaAtualId ?? this.etapaAtualId,
    assunto: assunto,
    prioridade: prioridade,
    atendenteHumanoId: atendenteHumanoId,
    dataInicio: dataInicio,
    dataUltimaMensagem: dataUltimaMensagem,
    sentimentoNota: sentimentoNota,
    sentimentoLabel: sentimentoLabel,
    naoLidas: naoLidas ?? this.naoLidas,
    contatoNome: contatoNome,
    contatoTelefone: contatoTelefone,
    contatoFotoUrl: contatoFotoUrl,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtendimentoResumo &&
          other.id == id &&
          other.etapaAtualId == etapaAtualId &&
          other.status == status &&
          other.naoLidas == naoLidas;

  @override
  int get hashCode => Object.hash(id, etapaAtualId, status, naoLidas);
}
