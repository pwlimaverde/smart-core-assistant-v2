import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';
import '../services/tenant_admin_service.dart';

final class UpdateMyTenantConfigUsecase {
  final TenantAdminService _service;

  const UpdateMyTenantConfigUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call(TenantConfig config) =>
      _service.updateMyTenantConfig(config);
}
