import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/evolution_connection_result.dart';
import '../services/admin_service.dart';

final class TestEvolutionConnectionUsecase {
  final AdminService _service;

  const TestEvolutionConnectionUsecase({required this._service});

  Future<ReturnSuccessOrError<EvolutionConnectionResult>> call(String tenantId) =>
      _service.testEvolutionConnection(tenantId);
}
