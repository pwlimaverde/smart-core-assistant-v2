/// P18 — quantos vínculos de um tenant, com um papel, dependem do fallback.
final class GrupoAMigrar {
  final String tenantId;
  final String tenantNome;
  final String papel;
  final int quantidade;

  const GrupoAMigrar({
    required this.tenantId,
    required this.tenantNome,
    required this.papel,
    required this.quantidade,
  });
}

/// P18 — o resultado (ou a prévia) de tornar explícitos os escopos implícitos.
final class ResultadoDaMigracao {
  final List<GrupoAMigrar> contagens;

  /// Vínculos que dependem do fallback do papel.
  final int total;

  /// Gravados de fato (0 na prévia).
  final int migrados;

  /// Mudaram no meio ou falharam — ficam para uma próxima rodada.
  final int pulados;

  /// `true` = prévia: nada foi gravado.
  final bool simulacao;

  const ResultadoDaMigracao({
    required this.contagens,
    required this.total,
    required this.migrados,
    required this.pulados,
    required this.simulacao,
  });
}
