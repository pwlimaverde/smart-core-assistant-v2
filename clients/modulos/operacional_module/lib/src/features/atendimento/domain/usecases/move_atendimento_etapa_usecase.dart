import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/atendimento_service.dart';

final class MoveAtendimentoEtapaUsecase {
  final AtendimentoService _service;

  const MoveAtendimentoEtapaUsecase({required AtendimentoService service})
    : _service = service; // ignore: prefer_initializing_formals

  Future<ReturnSuccessOrError<Unit>> call({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) => _service.moveAtendimentoEtapa(
    atendimentoId: atendimentoId,
    etapaDestinoId: etapaDestinoId,
    motivo: motivo,
  );
}
