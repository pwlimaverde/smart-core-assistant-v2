import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';
import '../services/admin_service.dart';

final class GetTenantConfigUsecase {
  final AdminService _service;

  const GetTenantConfigUsecase({required this._service});

  Future<ReturnSuccessOrError<TenantConfig>> call(String tenantId) => _service.getTenantConfig(tenantId);
}
