import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/tenant.dart';
import '../services/admin_service.dart';

final class CreateTenantUsecase {
  final AdminService _service;

  const CreateTenantUsecase({required this._service});

  Future<ReturnSuccessOrError<Tenant>> call({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) =>
      _service.createTenant(
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      );
}
