import 'package:return_success_or_error/return_success_or_error.dart';

/// Colunas de um quadro. Vêm do fluxo cadastrado, não dos atendimentos: uma
/// coluna sem conversa precisa aparecer, senão não há para onde arrastar.
final class ListColunasParameters extends Parameters {
  final int fluxoId;

  const ListColunasParameters({required this.fluxoId});
}

/// Muda o status do atendimento; o servidor move o cartão junto.
final class SetAtendimentoStatusParameters extends Parameters {
  final int atendimentoId;
  final String status;
  final String motivo;

  const SetAtendimentoStatusParameters({
    required this.atendimentoId,
    required this.status,
    this.motivo = '',
  });
}
