import 'package:return_success_or_error/return_success_or_error.dart';

/// Acrescenta um número à lista.
final class CriarIgnoradoParameters extends Parameters {
  final String nome;
  final String telefone;

  const CriarIgnoradoParameters({required this.nome, required this.telefone});
}

/// Corrige o cadastro ou liga/desliga a regra.
final class AtualizarIgnoradoParameters extends Parameters {
  final int id;
  final String nome;
  final String telefone;
  final bool ativo;

  const AtualizarIgnoradoParameters({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.ativo,
  });
}

/// Identifica o registro — usado por remover.
final class IgnoradoIdParameters extends Parameters {
  final int id;

  const IgnoradoIdParameters({required this.id});
}
