import 'package:return_success_or_error/return_success_or_error.dart';

/// P4 — quem cuida da conversa.
///
/// [atendenteId] nulo com [devolverParaFila] falso significa "a mim": quem
/// resolve o atendente é o servidor, pelo usuário do token.
final class AtribuirAtendimentoParameters extends Parameters {
  final int atendimentoId;
  final int? atendenteId;
  final bool devolverParaFila;

  const AtribuirAtendimentoParameters({
    required this.atendimentoId,
    this.atendenteId,
    this.devolverParaFila = false,
  });
}

/// P4 — urgência do cartão: `baixa`, `normal`, `alta` ou `urgente`.
final class DefinirPrioridadeParameters extends Parameters {
  final int atendimentoId;
  final String prioridade;

  const DefinirPrioridadeParameters({
    required this.atendimentoId,
    required this.prioridade,
  });
}

/// P4 — leva a conversa para outro fluxo do quadro.
final class TransferirParaFluxoParameters extends Parameters {
  final int atendimentoId;
  final int fluxoId;

  const TransferirParaFluxoParameters({
    required this.atendimentoId,
    required this.fluxoId,
  });
}

/// P4 — o quadro em CSV, no mesmo recorte que está na tela.
final class ExportarQuadroParameters extends Parameters {
  final String status;
  final int? departamentoId;
  final String busca;
  final bool somenteMeus;
  final bool somenteNaoLidos;

  const ExportarQuadroParameters({
    this.status = '',
    this.departamentoId,
    this.busca = '',
    this.somenteMeus = false,
    this.somenteNaoLidos = false,
  });
}
