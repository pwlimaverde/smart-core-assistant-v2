import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class UpdateTenantUsecase {
  final AdminService _service;

  const UpdateTenantUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) =>
      _service.updateTenant(
        id: id,
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      );
}
