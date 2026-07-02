import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/atendimento_resumo.dart';
import '../services/atendimento_service.dart';

final class ListAtendimentosUsecase {
  final AtendimentoService _service;

  const ListAtendimentosUsecase({required AtendimentoService service})
    : _service = service; // ignore: prefer_initializing_formals

  Future<ReturnSuccessOrError<List<AtendimentoResumo>>> call({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) => _service.listAtendimentos(
    status: status,
    departamentoId: departamentoId,
    limit: limit,
  );
}
