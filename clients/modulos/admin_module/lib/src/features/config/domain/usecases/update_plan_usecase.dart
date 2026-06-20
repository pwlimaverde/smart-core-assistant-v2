import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class UpdatePlanUsecase {
  final AdminService _service;

  const UpdatePlanUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  }) =>
      _service.updatePlan(
        id: id,
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
        active: active,
      );
}
