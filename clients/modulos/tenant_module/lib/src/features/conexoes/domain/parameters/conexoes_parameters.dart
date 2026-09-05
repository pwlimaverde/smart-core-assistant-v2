import 'package:return_success_or_error/return_success_or_error.dart';

/// Identifica a conexão — usado por reconectar e remover.
final class ConexaoIdParameters extends Parameters {
  final int id;

  const ConexaoIdParameters({required this.id});
}

/// Nome da instância no provedor — precisa ser único entre todos os tenants,
/// e é o servidor quem recusa a repetição.
final class CriarConexaoParameters extends Parameters {
  final String nome;

  const CriarConexaoParameters({required this.nome});
}
