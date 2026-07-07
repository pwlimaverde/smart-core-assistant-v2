import '../model/atendimento_evento.dart';
import '../model/atendimento_resumo.dart';
import '../model/mensagem_thread.dart';

/// Port (abstração) da fronteira operacional de Atendimento — WS-6.
///
/// RemoteOnly hoje (`AtendimentoRemoteDataSource` via gRPC-Web); preparado para
/// trocar por `LocalEngineFFI` no futuro (Windows/F8) sem tocar as telas — DIP:
/// controllers/telas dependem SOMENTE desta abstração, injetada por `get_it`.
/// Cada implementação lança a exceção tipada (`AppError` de `domain_models`)
/// diretamente — a camada de serviço (`AtendimentoService`) encapsula em
/// `ReturnSuccessOrError`, seguindo o padrão do `admin_module`.
abstract interface class AtendimentoDataSource {
  /// Lista a fila de atendimentos por status/departamento (Kanban — WS-6.2).
  Future<List<AtendimentoResumo>> listAtendimentos({
    String status,
    int? departamentoId,
    int limit,
  });

  /// Carrega o thread (histórico de mensagens) de um atendimento — chat lateral.
  Future<List<MensagemThread>> getThread({
    required int atendimentoId,
    int limit,
    int offset,
  });

  /// Move um atendimento para outra etapa do Kanban (drag-and-drop). O RBAC
  /// fino por fluxo é 100% server-side — falha aqui não precisa reimplementar
  /// nenhuma lógica de permissão, só propagar o erro do backend.
  Future<void> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo,
  });

  /// Envia (persiste) uma mensagem outbound do atendente no thread do
  /// atendimento; devolve o id da mensagem persistida.
  Future<int> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo,
  });

  /// Abre o stream realtime de eventos de atendimento do tenant (fila/Kanban/
  /// chat). Cada reconexão (após queda) deve chamar este método novamente —
  /// a política de backoff mora na camada de apresentação (WS-6.3).
  Stream<AtendimentoEvento> streamAtendimentos();
}
