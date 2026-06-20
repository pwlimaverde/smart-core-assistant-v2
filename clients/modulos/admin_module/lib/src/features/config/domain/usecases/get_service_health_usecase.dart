import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/service_health.dart';
import '../services/admin_service.dart';

final class GetServiceHealthUsecase {
  final AdminService _service;

  const GetServiceHealthUsecase({required this._service});

  Future<ReturnSuccessOrError<List<ServiceHealth>>> call() => _service.getServiceHealth();
}
