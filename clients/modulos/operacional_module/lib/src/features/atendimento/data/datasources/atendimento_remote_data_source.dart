import 'dart:convert';

import 'package:api_client/api_client.dart' as proto;
import 'package:domain_models/domain_models.dart';

import '../../domain/datasources/atendimento_data_source.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../grpc_error_mapper.dart';

/// Implementação RemoteOnly do [AtendimentoDataSource] via gRPC-Web
/// (`AdminServiceClient`) — WS-6.1.
///
/// Único ponto do módulo que fala com o transporte: nenhuma outra camada
/// (usecases/controllers/telas) referencia `proto.*`/gRPC diretamente (DIP).
/// Web usa este adapter hoje; Windows trocará por `LocalEngineFFI` no futuro
/// sem alterar telas/controllers — ambos implementam o mesmo port.
final class AtendimentoRemoteDataSource implements AtendimentoDataSource {
  final proto.AdminServiceClient _client;

  const AtendimentoRemoteDataSource({required proto.AdminServiceClient client})
    : _client = client; // ignore: prefer_initializing_formals

  @override
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    try {
      final resp = await _client.listAtendimentos(
        proto.ListAtendimentosRequest(
          status: status,
          departamentoId: departamentoId ?? 0,
          limit: limit,
        ),
      );
      return resp.atendimentos.map(_paraAtendimentoResumo).toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final resp = await _client.getThread(
        proto.GetThreadRequest(
          atendimentoId: atendimentoId,
          limit: limit,
          offset: offset,
        ),
      );
      return resp.mensagens.map(_paraMensagemThread).toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async {
    try {
      await _client.moveAtendimentoEtapa(
        proto.MoveAtendimentoEtapaRequest(
          atendimentoId: atendimentoId,
          etapaDestinoId: etapaDestinoId,
          motivo: motivo,
        ),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async {
    try {
      // NUNCA logar `conteudo` (PII) — só trafega no corpo da chamada RPC.
      final resp = await _client.sendOutboundMessage(
        proto.SendOutboundMessageRequest(
          atendimentoId: atendimentoId,
          conteudo: conteudo,
          tipo: tipo,
        ),
      );
      return resp.messageId;
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Stream<AtendimentoEvento> streamAtendimentos() {
    final responseStream = _client.streamAtendimentos(
      proto.StreamAtendimentosRequest(),
    );
    return responseStream.map(_paraAtendimentoEvento).handleError((
      Object e,
      StackTrace st,
    ) {
      if (e is proto.GrpcError) {
        throw mapGrpcError(e, const ErrorNetwork());
      }
      throw ErrorNetwork(message: '$e');
    });
  }

  static AtendimentoResumo _paraAtendimentoResumo(
    proto.AtendimentoResumo a,
  ) => AtendimentoResumo(
    id: a.id,
    contatoId: a.contatoId,
    status: a.status,
    departamentoId: a.departamentoId > 0 ? a.departamentoId : null,
    fluxoAtendimentoId: a.fluxoAtendimentoId > 0 ? a.fluxoAtendimentoId : null,
    etapaAtualId: a.etapaAtualId > 0 ? a.etapaAtualId : null,
    assunto: a.assunto,
    prioridade: a.prioridade,
    atendenteHumanoId: a.atendenteHumanoId > 0 ? a.atendenteHumanoId : null,
    dataInicio: DateTime.fromMillisecondsSinceEpoch(a.dataInicio.toInt()),
    dataUltimaMensagem: a.dataUltimaMensagem.toInt() > 0
        ? DateTime.fromMillisecondsSinceEpoch(a.dataUltimaMensagem.toInt())
        : null,
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
