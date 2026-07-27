import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/audit_log_entry.dart';
import '../../domain/parameters/audit_parameters.dart';

/// Datasources da feature `audit`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Consulta o log de auditoria com filtros.
final class QueryAuditLogDatasource
    implements Datasource<List<AuditLogEntry>, QueryAuditLogParameters> {
  final proto.AdminServiceClient _client;

  const QueryAuditLogDatasource({required this._client});

  @override
  Future<List<AuditLogEntry>> call(QueryAuditLogParameters parameters) async {
    final resp = await _client.queryAuditLog(
      proto.QueryAuditLogRequest(
        tenantId: parameters.tenantId ?? '',
        eventType: parameters.eventType ?? '',
        limit: parameters.limit ?? 50,
        offset: parameters.offset ?? 0,
      ),
    );
    return resp.entries
        .map(
          (a) => AuditLogEntry(
            id: a.id,
            eventType: a.eventType,
            actor: a.actor,
            tenantId: a.tenantId,
            description: a.description,
            ipAddress: a.ipAddress,
            userAgent: a.userAgent,
            createdAt: DateTime.fromMillisecondsSinceEpoch(a.createdAt.toInt()),
          ),
        )
        .toList();
  }
}
