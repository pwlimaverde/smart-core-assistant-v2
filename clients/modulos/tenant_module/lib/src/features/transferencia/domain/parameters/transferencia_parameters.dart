import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/transferencia.dart';

/// Cria (id 0) ou atualiza uma regra.
final class SalvarRegraParameters extends Parameters {
  final RegraDeTransferencia regra;

  const SalvarRegraParameters(this.regra);
}

/// Ativa ou desativa. Desativar exige o nome da regra em [confirmar].
final class RegraAtivaParameters extends Parameters {
  final int id;
  final bool ativa;
  final String confirmar;

  const RegraAtivaParameters({
    required this.id,
    required this.ativa,
    this.confirmar = '',
  });
}

/// Sinais e/ou fluxo padrão.
final class SinaisParameters extends Parameters {
  final List<SinalAutomatico> sinais;
  final bool alterarFluxoPadrao;
  final int? fluxoPadraoId;

  const SinaisParameters({
    this.sinais = const [],
    this.alterarFluxoPadrao = false,
    this.fluxoPadraoId,
  });
}

/// Uma frase contra uma regra (ainda não salva, ou salva).
final class TestarRegraParameters extends Parameters {
  final String frase;
  final RegraDeTransferencia regra;

  const TestarRegraParameters({required this.frase, required this.regra});
}
