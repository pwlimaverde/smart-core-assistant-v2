import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_config.dart';
import '../services/tenant_admin_service.dart';

final class GetMyTenantConfigUsecase {
  final TenantAdminService _service;

  const GetMyTenantConfigUsecase({required this._service});

  Future<ReturnSuccessOrError<TenantConfig>> call() => _service.getMyTenantConfig();
}
