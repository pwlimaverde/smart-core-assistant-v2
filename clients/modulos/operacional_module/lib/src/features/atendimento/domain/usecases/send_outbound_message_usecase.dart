import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/atendimento_service.dart';

final class SendOutboundMessageUsecase {
  final AtendimentoService _service;

  const SendOutboundMessageUsecase({required AtendimentoService service})
    : _service = service; // ignore: prefer_initializing_formals

  /// [conteudo] é PII — o usecase apenas encaminha, nunca loga.
  Future<ReturnSuccessOrError<int>> call({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) => _service.sendOutboundMessage(
    atendimentoId: atendimentoId,
    conteudo: conteudo,
    tipo: tipo,
  );
}
