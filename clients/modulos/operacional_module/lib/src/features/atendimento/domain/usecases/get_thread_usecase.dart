import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/mensagem_thread.dart';
import '../services/atendimento_service.dart';

final class GetThreadUsecase {
  final AtendimentoService _service;

  const GetThreadUsecase({required AtendimentoService service})
    : _service = service; // ignore: prefer_initializing_formals

  Future<ReturnSuccessOrError<List<MensagemThread>>> call({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) => _service.getThread(
    atendimentoId: atendimentoId,
    limit: limit,
    offset: offset,
  );
}
