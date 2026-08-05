import 'dart:async';

import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/data/streams/atendimento_evento_stream_impl.dart';
import 'package:operacional_module/src/features/atendimento/domain/gateways/atendimento_gateway.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ficha.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/quadro.dart';
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
  Object? erroStatus;
  Object? erroColunas;

  int chamadasList = 0;
  int chamadasThread = 0;
  int chamadasMove = 0;
  int chamadasSend = 0;
  int chamadasStatus = 0;

  /// Colunas do quadro devolvidas por [listColunas].
  List<ColunaDoQuadro> colunas = const [];
  List<FluxoDoQuadro> fluxos = const [];

  /// Último status pedido — para verificar o repasse.
  String? statusRecebido;

  /// Ficha devolvida por [getFicha].
  FichaAtendimento ficha = const FichaAtendimento(
    catalogo: [],
    aplicadas: [],
    notas: [],
  );
  Object? erroFicha;
  int chamadasFicha = 0;

  /// Últimos valores recebidos pelas escritas da ficha.
  String? notaRecebida;
  (int, bool)? etiquetaAlternada;
  String? etiquetaCriada;

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
  Future<void> setAtendimentoStatus({
    required int atendimentoId,
    required String status,
    String motivo = '',
  }) async {
    chamadasStatus++;
    statusRecebido = status;
    if (erroStatus != null) throw erroStatus!;
  }

  @override
  Future<List<FluxoDoQuadro>> listFluxos() async => fluxos;

  @override
  Future<List<ColunaDoQuadro>> listColunas(int fluxoId) async {
    if (erroColunas != null) throw erroColunas!;
    return colunas;
  }

  @override
  Future<FichaAtendimento> getFicha(int atendimentoId) async {
    chamadasFicha++;
    if (erroFicha != null) throw erroFicha!;
    return ficha;
  }

  @override
  Future<void> criarEtiqueta({
    required String nome,
    required String cor,
  }) async {
    etiquetaCriada = nome;
    if (erroFicha != null) throw erroFicha!;
  }

  @override
  Future<void> alternarEtiqueta({
    required int atendimentoId,
    required int etiquetaId,
    required bool aplicar,
  }) async {
    etiquetaAlternada = (etiquetaId, aplicar);
    if (erroFicha != null) throw erroFicha!;
  }

  @override
  Future<void> criarNota({
    required int atendimentoId,
    required String texto,
  }) async {
    notaRecebida = texto;
    if (erroFicha != null) throw erroFicha!;
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
  ListFluxosUsecase fluxos,
  ListColunasUsecase colunas,
  SetAtendimentoStatusUsecase status,
  GetFichaUsecase ficha,
  CriarEtiquetaUsecase criarEtiqueta,
  AlternarEtiquetaUsecase alternarEtiqueta,
  CriarNotaUsecase criarNota,
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
  fluxos: ListFluxosUsecase(
    repository: ListFluxosRepository(
      datasource: ListFluxosDatasource(gateway: gateway),
    ),
  ),
  colunas: ListColunasUsecase(
    repository: ListColunasRepository(
      datasource: ListColunasDatasource(gateway: gateway),
    ),
  ),
  status: SetAtendimentoStatusUsecase(
    repository: SetAtendimentoStatusRepository(
      datasource: SetAtendimentoStatusDatasource(gateway: gateway),
    ),
  ),
  ficha: GetFichaUsecase(
    repository: GetFichaRepository(
      datasource: GetFichaDatasource(gateway: gateway),
    ),
  ),
  criarEtiqueta: CriarEtiquetaUsecase(
    repository: CriarEtiquetaRepository(
      datasource: CriarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  alternarEtiqueta: AlternarEtiquetaUsecase(
    repository: AlternarEtiquetaRepository(
      datasource: AlternarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  criarNota: CriarNotaUsecase(
    repository: CriarNotaRepository(
      datasource: CriarNotaDatasource(gateway: gateway),
    ),
  ),
  eventos: AtendimentoEventoStreamImpl(gateway: gateway),
);

/// Colunas de um quadro padrao (fila -> trabalho -> finalizacao).
List<ColunaDoQuadro> colunasDeTeste() => const [
  ColunaDoQuadro(id: 10, nome: 'Entrada', cor: '#6B7280', ordem: 1, tipo: 'fila'),
  ColunaDoQuadro(
    id: 20,
    nome: 'Trabalhando',
    cor: '#3B82F6',
    ordem: 2,
    tipo: 'trabalho',
  ),
  ColunaDoQuadro(
    id: 30,
    nome: 'Fechado',
    cor: '#10B981',
    ordem: 3,
    tipo: 'finalizacao',
  ),
];

List<FluxoDoQuadro> fluxosDeTeste() => const [
  FluxoDoQuadro(id: 1, nome: 'Padrao', departamentoNome: 'Suporte'),
];

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

/// Dois quadros nomeados, para o teste do seletor.
abstract final class FluxoDoQuadroDeTeste {
  static const suporte = FluxoDoQuadro(
    id: 1,
    nome: 'Padrão',
    departamentoNome: 'Suporte',
  );
  static const comercial = FluxoDoQuadro(
    id: 2,
    nome: 'Vendas',
    departamentoNome: 'Comercial',
  );
}
