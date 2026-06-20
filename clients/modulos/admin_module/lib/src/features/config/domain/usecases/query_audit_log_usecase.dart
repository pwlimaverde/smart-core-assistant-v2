import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/audit_log_entry.dart';
import '../services/admin_service.dart';

final class QueryAuditLogUsecase {
  final AdminService _service;

  const QueryAuditLogUsecase({required this._service});

  Future<ReturnSuccessOrError<List<AuditLogEntry>>> call({
    String? tenantId,
    String? eventType,
    int? limit,
    int? offset,
  }) =>
      _service.queryAuditLog(
        tenantId: tenantId,
        eventType: eventType,
        limit: limit,
        offset: offset,
      );
}
