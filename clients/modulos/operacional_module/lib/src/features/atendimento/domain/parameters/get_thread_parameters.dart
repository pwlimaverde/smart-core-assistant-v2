import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para carregar o thread (histórico de mensagens) de um
/// atendimento — chat lateral (WS-6.3).
final class GetThreadParameters extends Parameters {
  final int atendimentoId;
  final int limit;
  final int offset;

  const GetThreadParameters({
    required this.atendimentoId,
    this.limit = 50,
    this.offset = 0,
  });
}
