import 'package:presentation_module/presentation_module.dart';
import '../../domain/model/dashboard_summary.dart';
import '../../domain/usecases/get_dashboard_summary_usecase.dart';

final class DashboardController extends BaseController<DashboardSummary> {
  final GetDashboardSummaryUsecase _getSummaryUsecase;

  DashboardController({
    required this._getSummaryUsecase,
  });

  Future<void> fetchSummary() => execute(() => _getSummaryUsecase.call());
}
