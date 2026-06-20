import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/model/audit_log_entry.dart';
import '../../domain/model/tenant.dart';
import '../../domain/usecases/query_audit_log_usecase.dart';
import '../../domain/usecases/export_tenants_csv_usecase.dart';
import '../../domain/usecases/list_tenants_usecase.dart';

final class AuditController extends BaseController<List<AuditLogEntry>> {
  final QueryAuditLogUsecase _queryUsecase;
  final ExportTenantsCsvUsecase _exportUsecase;
  final ListTenantsUsecase _listTenantsUsecase;

  AuditController({
    required this._queryUsecase,
    required this._exportUsecase,
    required this._listTenantsUsecase,
  });

  Future<void> fetchAuditLogs({
    String? tenantId,
    String? eventType,
    int? limit,
    int? offset,
  }) =>
      execute(() => _queryUsecase.call(
            tenantId: tenantId,
            eventType: eventType,
            limit: limit,
            offset: offset,
          ));

  Future<ReturnSuccessOrError<List<int>>> exportTenantsCsv() => _exportUsecase.call();

  Future<ReturnSuccessOrError<List<Tenant>>> getTenants() => _listTenantsUsecase.call();
}
