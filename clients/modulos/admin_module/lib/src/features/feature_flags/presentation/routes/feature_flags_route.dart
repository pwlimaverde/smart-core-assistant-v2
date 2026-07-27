import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/feature_flags_controller.dart';
import '../pages/feature_flags_page.dart';
import '../../domain/usecases/feature_flags_usecases.dart';
import '../../../tenants/domain/usecases/tenants_usecases.dart';

final class FeatureFlagsRoute extends GetItModule {
  @override
  String get path => '/admin/feature-flags';

  @override
  Widget get page => const FeatureFlagsPage();

  @override
  void binds(Injector i) {
    i.controller<FeatureFlagsController>(
      () => FeatureFlagsController(
        listUsecase: inject<ListFeatureFlagsUsecase>(),
        setUsecase: inject<SetFeatureFlagUsecase>(),
        setOverrideUsecase: inject<SetFeatureFlagOverrideUsecase>(),
        listTenantsUsecase: inject<ListTenantsUsecase>(),
      ),
    );
  }
}
