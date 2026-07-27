import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/dashboard_controller.dart';
import '../pages/dashboard_page.dart';
import '../../domain/usecases/dashboard_usecases.dart';

final class DashboardRoute extends GetItModule {
  @override
  String get path => '/admin/dashboard';

  @override
  Widget get page => const DashboardPage();

  @override
  void binds(Injector i) {
    i.controller<DashboardController>(
      () => DashboardController(
        getSummaryUsecase: inject<GetDashboardSummaryUsecase>(),
      ),
    );
  }
}
