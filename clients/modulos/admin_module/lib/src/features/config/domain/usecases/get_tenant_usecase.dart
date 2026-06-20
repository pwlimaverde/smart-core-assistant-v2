import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant.dart';
import '../services/admin_service.dart';

final class GetTenantUsecase {
  final AdminService _service;

  const GetTenantUsecase({required this._service});

  Future<ReturnSuccessOrError<Tenant>> call(String id) => _service.getTenant(id);
}
