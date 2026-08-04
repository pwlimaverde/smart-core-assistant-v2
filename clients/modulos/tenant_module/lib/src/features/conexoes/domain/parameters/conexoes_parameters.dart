import 'package:return_success_or_error/return_success_or_error.dart';

/// Identifica a conexão — usado por reconectar e remover.
final class ConexaoIdParameters extends Parameters {
  final int id;

  const ConexaoIdParameters({required this.id});
}
