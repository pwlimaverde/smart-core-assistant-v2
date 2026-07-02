import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/atendimento_evento.dart';
import '../model/atendimento_resumo.dart';
import '../model/mensagem_thread.dart';

/// Serviço de domínio do Atendimento: fronteira consumida pelos usecases/
/// controllers, devolvendo sempre [ReturnSuccessOrError] (nunca lança).
///
/// Implementado por [AtendimentoServiceImpl], que delega ao
/// [AtendimentoDataSource] injetado (RemoteOnly hoje).
abstract interface class AtendimentoService {
  Future<ReturnSuccessOrError<List<AtendimentoResumo>>> listAtendimentos({
    String status,
    int? departamentoId,
    int limit,
  });

  Future<ReturnSuccessOrError<List<MensagemThread>>> getThread({
    required int atendimentoId,
    int limit,
    int offset,
  });

  Future<ReturnSuccessOrError<Unit>> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo,
  });

  Future<ReturnSuccessOrError<int>> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo,
  });

  /// Stream realtime "cru" (sem catch — erros/queda do stream propagam como
  /// erro do próprio `Stream`; a política de reconexão vive na apresentação).
  Stream<AtendimentoEvento> streamAtendimentos();
}
