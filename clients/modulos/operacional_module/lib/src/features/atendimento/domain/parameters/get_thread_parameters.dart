import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para carregar o thread (histórico de mensagens) de um
/// atendimento — chat lateral (WS-6.3).
final class GetThreadParameters extends Parameters {
  final int atendimentoId;
  final int limit;
  final int offset;

  /// P2 — carrega o que veio **antes** desta mensagem (rolagem para cima).
  /// Quando presente, o servidor ignora o [offset]: numa conversa que segue
  /// recebendo, paginar por offset repete ou pula bolha.
  final int? beforeId;

  const GetThreadParameters({
    required this.atendimentoId,
    this.limit = 50,
    this.offset = 0,
    this.beforeId,
  });
}
