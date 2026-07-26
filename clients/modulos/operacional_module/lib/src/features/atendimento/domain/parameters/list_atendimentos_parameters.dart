import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para listar a fila de atendimentos por status/departamento
/// (WS-6.2). `departamentoId == null` lista todos os departamentos.
final class ListAtendimentosParameters extends Parameters {
  final String status;
  final int? departamentoId;
  final int limit;

  const ListAtendimentosParameters({
    this.status = 'fila',
    this.departamentoId,
    this.limit = 50,
  });
}
