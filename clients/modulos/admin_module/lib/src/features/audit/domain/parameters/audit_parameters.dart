import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações da feature `audit`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Consulta o log de auditoria com filtros.
final class QueryAuditLogParameters extends Parameters {
  final String? tenantId;
  final String? eventType;
  final int? limit;
  final int? offset;

  const QueryAuditLogParameters({
    this.tenantId,
    this.eventType,
    this.limit,
    this.offset,
  });
}
