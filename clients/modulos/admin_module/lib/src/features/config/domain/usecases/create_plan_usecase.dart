import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/plan.dart';
import '../services/admin_service.dart';

final class CreatePlanUsecase {
  final AdminService _service;

  const CreatePlanUsecase({required this._service});

  Future<ReturnSuccessOrError<Plan>> call({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  }) =>
      _service.createPlan(
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
      );
}
