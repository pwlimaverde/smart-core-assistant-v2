import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/usecases/dashboard_usecases.dart';
import '../../domain/model/dashboard_summary.dart';

final class DashboardController extends BaseController<DashboardSummary> {
  final GetDashboardSummaryUsecase _getSummaryUsecase;

  DashboardController({required this._getSummaryUsecase});

  Future<void> fetchSummary() => execute(() => _getSummaryUsecase(noParams));
}
