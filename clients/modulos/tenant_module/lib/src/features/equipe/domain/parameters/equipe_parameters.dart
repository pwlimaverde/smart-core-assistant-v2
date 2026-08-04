import 'package:return_success_or_error/return_success_or_error.dart';

final class CriarDepartamentoParameters extends Parameters {
  final String nome;
  final String descricao;

  const CriarDepartamentoParameters({
    required this.nome,
    required this.descricao,
  });
}

final class AtualizarDepartamentoParameters extends Parameters {
  final int id;
  final String nome;
  final String descricao;
  final bool ativo;

  const AtualizarDepartamentoParameters({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.ativo,
  });
}

final class DepartamentoIdParameters extends Parameters {
  final int id;

  const DepartamentoIdParameters({required this.id});
}
