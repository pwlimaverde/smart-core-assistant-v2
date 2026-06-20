import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/plan.dart';
import '../services/admin_service.dart';

final class ListPlansUsecase {
  final AdminService _service;

  const ListPlansUsecase({required this._service});

  Future<ReturnSuccessOrError<List<Plan>>> call() => _service.listPlans();
}
