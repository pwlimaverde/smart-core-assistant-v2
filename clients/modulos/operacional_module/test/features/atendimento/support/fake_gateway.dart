import 'dart:async';

import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/data/streams/atendimento_evento_stream_impl.dart';
import 'package:operacional_module/src/features/atendimento/domain/gateways/atendimento_gateway.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';

/// Gateway falso: substitui a plataforma (gRPC-Web ou motor local) por dados em
/// memória. Como é o **único** ponto trocado, os testes que o usam exercitam a
/// cadeia real acima dele — datasource, `mapError` do repositório e `process` do
/// usecase.
final class FakeAtendimentoGateway implements AtendimentoGateway {
  List<AtendimentoResumo> fila;
  List<MensagemThread> thread;
  int messageId;

  /// Exceção a lançar na próxima chamada de cada operação (`null` = sucesso).
  Object? erroList;
  Object? erroThread;
  Object? erroMove;
  Object? erroSend;

  int chamadasList = 0;
  int chamadasThread = 0;
  int chamadasMove = 0;
  int chamadasSend = 0;

  /// Último `motivo` recebido pelo move — para verificar o repasse.
  String? motivoRecebido;

  final StreamController<AtendimentoEvento> eventos;

  FakeAtendimentoGateway({
    this.fila = const [],
    this.thread = const [],
    this.messageId = 1,
    StreamController<AtendimentoEvento>? eventos,
  }) : eventos = eventos ?? StreamController<AtendimentoEvento>.broadcast();

  @override
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    chamadasList++;
    if (erroList != null) throw erroList!;
    return fila;
  }

  @override
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async {
    chamadasThread++;
    if (erroThread != null) throw erroThread!;
    return thread;
  }

  @override
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async {
    chamadasMove++;
    motivoRecebido = motivo;
    if (erroMove != null) throw erroMove!;
  }

  @override
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async {
    chamadasSend++;
    if (erroSend != null) throw erroSend!;
    return messageId;
  }

  @override
  Stream<AtendimentoEvento> streamAtendimentos() => eventos.stream;
}

/// Monta os usecases reais sobre um [FakeAtendimentoGateway].
({
  ListAtendimentosUsecase list,
  GetThreadUsecase thread,
  MoveAtendimentoEtapaUsecase move,
  SendOutboundMessageUsecase send,
  AtendimentoEventoStream eventos,
})
usecasesSobre(FakeAtendimentoGateway gateway) => (
  list: ListAtendimentosUsecase(
    repository: ListAtendimentosRepository(
      datasource: ListAtendimentosDatasource(gateway: gateway),
    ),
  ),
  thread: GetThreadUsecase(
    repository: GetThreadRepository(
      datasource: GetThreadDatasource(gateway: gateway),
    ),
  ),
  move: MoveAtendimentoEtapaUsecase(
    repository: MoveAtendimentoEtapaRepository(
      datasource: MoveAtendimentoEtapaDatasource(gateway: gateway),
    ),
  ),
  send: SendOutboundMessageUsecase(
    repository: SendOutboundMessageRepository(
      datasource: SendOutboundMessageDatasource(gateway: gateway),
    ),
  ),
  eventos: AtendimentoEventoStreamImpl(gateway: gateway),
);

AtendimentoResumo atendimentoDeTeste({
  required int id,
  int? etapaAtualId,
  String prioridade = 'normal',
  DateTime? dataUltimaMensagem,
}) => AtendimentoResumo(
  id: id,
  contatoId: id,
  status: 'fila',
  etapaAtualId: etapaAtualId,
  assunto: 'Assunto $id',
  prioridade: prioridade,
  dataInicio: DateTime(2026, 1, 1),
  dataUltimaMensagem: dataUltimaMensagem,
);

MensagemThread mensagemDeTeste({
  required int id,
  required DateTime timestamp,
  String remetente = 'cliente',
  String conteudo = 'oi',
}) => MensagemThread(
  id: id,
  atendimentoId: 1,
  tipo: 'texto',
  conteudo: conteudo,
  remetente: remetente,
  timestamp: timestamp,
  statusEnvio: 'enviado',
  geradoPorIa: false,
);
