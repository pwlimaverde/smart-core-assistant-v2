import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/dashboard_summary.dart';
import '../services/admin_service.dart';

final class GetDashboardSummaryUsecase {
  final AdminService _service;

  const GetDashboardSummaryUsecase({required this._service});

  Future<ReturnSuccessOrError<DashboardSummary>> call() => _service.getDashboardSummary();
}
