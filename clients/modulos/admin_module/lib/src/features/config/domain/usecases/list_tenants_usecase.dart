import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant.dart';
import '../services/admin_service.dart';

final class ListTenantsUsecase {
  final AdminService _service;

  const ListTenantsUsecase({required this._service});

  Future<ReturnSuccessOrError<List<Tenant>>> call() => _service.listTenants();
}
