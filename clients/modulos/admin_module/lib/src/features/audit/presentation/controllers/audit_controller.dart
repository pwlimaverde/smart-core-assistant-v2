import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/usecases/audit_usecases.dart';
import '../../domain/parameters/audit_parameters.dart';
import '../../domain/model/audit_log_entry.dart';
import '../../../tenants/domain/errors/tenants_errors.dart';
import '../../../tenants/domain/model/tenant.dart';
import '../../../tenants/domain/usecases/tenants_usecases.dart';

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
  }) => execute(
    () => _queryUsecase(
      QueryAuditLogParameters(
        tenantId: tenantId,
        eventType: eventType,
        limit: limit,
        offset: offset,
      ),
    ),
  );

  Future<ReturnSuccessOrError<List<int>, TenantsError>> exportTenantsCsv() =>
      _exportUsecase(noParams);

  Future<ReturnSuccessOrError<List<Tenant>, TenantsError>> getTenants() =>
      _listTenantsUsecase(noParams);
}
