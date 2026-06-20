import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';
import '../services/admin_service.dart';

final class UpdateTenantConfigUsecase {
  final AdminService _service;

  const UpdateTenantConfigUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required String tenantId,
    required TenantConfig config,
  }) =>
      _service.updateTenantConfig(
        tenantId: tenantId,
        config: config,
      );
}
