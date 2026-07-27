import '../model/atendimento_evento.dart';
import '../model/atendimento_resumo.dart';
import '../model/mensagem_thread.dart';

/// Fronteira de infraestrutura do atendimento, **escolhida por plataforma**:
/// gRPC-Web no browser, motor local Rust (SQLite + fila offline) no desktop.
///
/// **Por que um gateway agregado e não um `Datasource` por operação:** o que
/// varia aqui é a *plataforma*, não a operação. Um único objeto trocado no boot
/// (por import condicional) mantém as quatro operações e o stream coerentes entre
/// si — no desktop, `listAtendimentos` e `sendOutboundMessage` compartilham o
/// mesmo índice SQLite e a mesma fila. Quebrar isso em oito classes (4 operações
/// × 2 plataformas) espalharia essa coerência por uma matriz.
///
/// Os `Datasource<TData, TParams>` da `return_success_or_error` ficam **em cima**
/// deste port: são adaptadores finos, um por operação, que traduzem
/// `Parameters` → chamada do gateway. É a costura entre o eixo "plataforma"
/// (aqui) e o eixo "operação" (a lib).
///
/// Como todo datasource na v3, este port é **burro**: devolve o dado ou deixa a
/// exceção técnica subir crua (`GrpcError` no Web, [LocalEngineFalha] no
/// desktop). Traduzir para erro de domínio é trabalho do `mapError` de cada
/// repositório — antes, cada adapter fazia isso por conta própria e o resultado
/// era `ErrorNetwork(message: '$e')` chegando à tela.
abstract interface class AtendimentoGateway {
  /// Lista a fila de atendimentos por status/departamento (Kanban — WS-6.2).
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status,
    int? departamentoId,
    int limit,
  });

  /// Carrega o thread (histórico de mensagens) de um atendimento.
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit,
    int offset,
  });

  /// Move um atendimento para outra etapa do Kanban (drag-and-drop).
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo,
  });

  /// Persiste uma mensagem outbound do atendente; devolve o id da mensagem.
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo,
  });

  /// Abre o stream realtime de eventos do tenant (fila/Kanban/chat).
  ///
  /// Cada reconexão chama este método novamente — a política de backoff mora na
  /// apresentação (WS-6.3). Erros e o encerramento chegam como erro/fim do
  /// próprio `Stream`: não há `ReturnSuccessOrError` aqui porque a lib é
  /// request/response, e embrulhar um fluxo contínuo nela esconderia justamente
  /// o que a UI precisa observar.
  Stream<AtendimentoEvento> streamAtendimentos();
}

/// Falha do motor local (FFI/`local_engine`): índice SQLite, fila offline, cache
/// de mídia ou sincronização.
///
/// É uma **exceção técnica**, não um erro de domínio: existe para que o
/// `mapError` de cada repositório consiga distinguir "o armazenamento local
/// falhou" de "a rede falhou" — desfechos com ações diferentes para o usuário
/// (reiniciar o app vs. tentar de novo). A mensagem do motor descreve
/// storage/sync/io/mídia e não carrega PII.
final class LocalEngineFalha implements Exception {
  final String message;
  final Object causa;

  const LocalEngineFalha(this.message, this.causa);

  @override
  String toString() => 'LocalEngineFalha - $message';
}
