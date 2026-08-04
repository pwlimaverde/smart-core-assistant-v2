import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/fluxo.dart';

final class CriarFluxoParameters extends Parameters {
  final int departamentoId;
  final String nome;
  final String descricao;

  const CriarFluxoParameters({
    required this.departamentoId,
    required this.nome,
    required this.descricao,
  });
}

final class AtualizarFluxoParameters extends Parameters {
  final int id;
  final String nome;
  final String descricao;
  final bool ativo;

  const AtualizarFluxoParameters({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.ativo,
  });
}

final class FluxoIdParameters extends Parameters {
  final int id;

  const FluxoIdParameters({required this.id});
}

final class CriarEtapaParameters extends Parameters {
  final int fluxoId;
  final String nome;
  final TipoEtapa tipo;
  final String cor;

  const CriarEtapaParameters({
    required this.fluxoId,
    required this.nome,
    required this.tipo,
    required this.cor,
  });
}

final class AtualizarEtapaParameters extends Parameters {
  final int id;
  final String nome;
  final String descricao;
  final String cor;
  final TipoEtapa tipo;

  const AtualizarEtapaParameters({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.cor,
    required this.tipo,
  });
}

final class EtapaIdParameters extends Parameters {
  final int id;

  const EtapaIdParameters({required this.id});
}

final class MoverEtapaParameters extends Parameters {
  final int id;
  final bool paraCima;

  const MoverEtapaParameters({required this.id, required this.paraCima});
}
