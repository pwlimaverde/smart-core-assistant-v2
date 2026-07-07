import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para carregar o thread (histórico de mensagens) de um
/// atendimento — chat lateral (WS-6.3).
final class GetThreadParameters implements ParametersReturnResult {
  final int atendimentoId;
  final int limit;
  final int offset;

  @override
  final AppError error;

  const GetThreadParameters({
    required this.atendimentoId,
    this.limit = 50,
    this.offset = 0,
    required this.error,
  });
}
