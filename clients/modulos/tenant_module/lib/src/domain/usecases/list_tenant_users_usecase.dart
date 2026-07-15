import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant_user.dart';
import '../services/tenant_admin_service.dart';

final class ListTenantUsersUsecase {
  final TenantAdminService _service;

  const ListTenantUsersUsecase({required this._service});

  Future<ReturnSuccessOrError<List<TenantUser>>> call() => _service.listTenantUsers();
}
