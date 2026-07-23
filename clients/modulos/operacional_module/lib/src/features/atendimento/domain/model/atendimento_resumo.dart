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
  });

  /// Cópia com a etapa (e opcionalmente o status) alterados — usada para
  /// aplicar otimisticamente o resultado de um drag-and-drop no Kanban antes
  /// da confirmação do servidor (revertida no erro).
  AtendimentoResumo copyWith({int? etapaAtualId, String? status}) =>
      AtendimentoResumo(
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
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AtendimentoResumo &&
          other.id == id &&
          other.etapaAtualId == etapaAtualId &&
          other.status == status;

  @override
  int get hashCode => Object.hash(id, etapaAtualId, status);
}
