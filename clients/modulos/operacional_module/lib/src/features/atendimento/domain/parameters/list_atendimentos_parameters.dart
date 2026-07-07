import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para listar a fila de atendimentos por status/departamento
/// (WS-6.2). `departamentoId == null` lista todos os departamentos.
final class ListAtendimentosParameters implements ParametersReturnResult {
  final String status;
  final int? departamentoId;
  final int limit;

  @override
  final AppError error;

  const ListAtendimentosParameters({
    this.status = 'fila',
    this.departamentoId,
    this.limit = 50,
    required this.error,
  });
}
