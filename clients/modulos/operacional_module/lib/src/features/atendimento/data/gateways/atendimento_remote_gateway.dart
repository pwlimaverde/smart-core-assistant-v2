import 'dart:convert';

import 'package:api_client/api_client.dart' as proto;

import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';

/// Adapter Web do [AtendimentoGateway] via gRPC-Web (`AdminServiceClient`).
///
/// Único ponto do módulo que fala com o transporte: nenhuma outra camada
/// (repositórios/usecases/controllers/telas) referencia `proto.*` (DIP). O
/// desktop usa `LocalEngineGateway` no lugar deste, sem mudar nada acima.
///
/// **Sem try/catch:** a exceção do transporte sobe crua para o `mapError` do
/// repositório. Antes, cada método traduzia por conta própria, e o `catch`
/// genérico interpolava a exceção na mensagem do erro — que terminava exibida na
/// tela.
final class AtendimentoRemoteGateway implements AtendimentoGateway {
  final proto.AdminServiceClient _client;

  const AtendimentoRemoteGateway({required this._client});

  @override
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    final resp = await _client.listAtendimentos(
      proto.ListAtendimentosRequest(
        status: status,
        departamentoId: departamentoId ?? 0,
        limit: limit,
      ),
    );
    return resp.atendimentos.map(_paraAtendimentoResumo).toList();
  }

  @override
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    final resp = await _client.getThread(
      proto.GetThreadRequest(
        atendimentoId: atendimentoId,
        limit: limit,
        offset: offset,
      ),
    );
    return resp.mensagens.map(_paraMensagemThread).toList();
  }

  @override
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async {
    await _client.moveAtendimentoEtapa(
      proto.MoveAtendimentoEtapaRequest(
        atendimentoId: atendimentoId,
        etapaDestinoId: etapaDestinoId,
        motivo: motivo,
      ),
    );
  }

  @override
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async {
    // NUNCA logar `conteudo` (PII) — só trafega no corpo da chamada RPC.
    final resp = await _client.sendOutboundMessage(
      proto.SendOutboundMessageRequest(
        atendimentoId: atendimentoId,
        conteudo: conteudo,
        tipo: tipo,
      ),
    );
    return resp.messageId;
  }

  @override
  Stream<AtendimentoEvento> streamAtendimentos() {
    // O erro do stream sobe cru: quem trata queda de conexão é a apresentação
    // (backoff exponencial + jitter), e ela decide com base no erro original.
    return _client
        .streamAtendimentos(proto.StreamAtendimentosRequest())
        .map(_paraAtendimentoEvento);
  }

  static AtendimentoResumo _paraAtendimentoResumo(proto.AtendimentoResumo a) =>
      AtendimentoResumo(
        id: a.id,
        contatoId: a.contatoId,
        status: a.status,
        departamentoId: a.departamentoId > 0 ? a.departamentoId : null,
        fluxoAtendimentoId: a.fluxoAtendimentoId > 0
            ? a.fluxoAtendimentoId
            : null,
        etapaAtualId: a.etapaAtualId > 0 ? a.etapaAtualId : null,
        assunto: a.assunto,
        prioridade: a.prioridade,
        atendenteHumanoId: a.atendenteHumanoId > 0 ? a.atendenteHumanoId : null,
        dataInicio: DateTime.fromMillisecondsSinceEpoch(a.dataInicio.toInt()),
        dataUltimaMensagem: a.dataUltimaMensagem.toInt() > 0
            ? DateTime.fromMillisecondsSinceEpoch(a.dataUltimaMensagem.toInt())
            : null,
        sentimentoNota: a.hasSentimentoNota() ? a.sentimentoNota : null,
        sentimentoLabel: a.hasSentimentoLabel() ? a.sentimentoLabel : null,
      );

  static MensagemThread _paraMensagemThread(proto.MensagemThread m) =>
      MensagemThread(
        id: m.id,
        atendimentoId: m.atendimentoId,
        tipo: m.tipo,
        conteudo: m.conteudo,
        remetente: m.remetente,
        timestamp: DateTime.fromMillisecondsSinceEpoch(m.timestamp.toInt()),
        statusEnvio: m.statusEnvio,
        geradoPorIa: m.geradoPorIa,
        resumoMidia: m.hasResumoMidia() ? m.resumoMidia : null,
      );

  static AtendimentoEvento _paraAtendimentoEvento(proto.AtendimentoEvent e) {
    Map<String, Object?> payload;
    try {
      final decoded = jsonDecode(e.payload);
      payload = decoded is Map<String, Object?> ? decoded : <String, Object?>{};
    } catch (_) {
      payload = <String, Object?>{};
    }
    return AtendimentoEvento(
      tipo: e.eventType,
      tenantId: e.tenantId,
      payload: payload,
    );
  }
}
