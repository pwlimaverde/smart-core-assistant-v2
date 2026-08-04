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

final class CriarAtendenteParameters extends Parameters {
  final String nome;
  final String email;
  final String cargo;
  final int fluxoId;

  /// 0 = sem departamento.
  final int departamentoId;

  const CriarAtendenteParameters({
    required this.nome,
    required this.email,
    required this.cargo,
    required this.fluxoId,
    required this.departamentoId,
  });
}

final class AtualizarAtendenteParameters extends Parameters {
  final int id;
  final String nome;
  final String cargo;
  final int departamentoId;
  final int fluxoId;
  final bool ativo;
  final bool disponivel;
  final int maxSimultaneos;

  const AtualizarAtendenteParameters({
    required this.id,
    required this.nome,
    required this.cargo,
    required this.departamentoId,
    required this.fluxoId,
    required this.ativo,
    required this.disponivel,
    required this.maxSimultaneos,
  });
}

final class AtendenteIdParameters extends Parameters {
  final int id;

  const AtendenteIdParameters({required this.id});
}
