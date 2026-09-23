final class EvolutionConnectionResult {
  final String status;
  final String errorMessage;

  const EvolutionConnectionResult({
    required this.status,
    required this.errorMessage,
  });
}

/// P9 — resultado do ensaio contra o provedor de IA do tenant.
///
/// `ok == false` não é falha do teste: é o teste descobrindo que o provedor não
/// responde — chave expirada, cota estourada, modelo removido.
final class TesteProvedorIa {
  final bool ok;
  final int latenciaMs;
  final int dimensoes;
  final String erro;

  const TesteProvedorIa({
    required this.ok,
    required this.latenciaMs,
    required this.dimensoes,
    required this.erro,
  });
}
