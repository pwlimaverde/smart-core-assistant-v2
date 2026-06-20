import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/list_feature_flags_usecase.dart';
import '../../domain/usecases/set_feature_flag_usecase.dart';
import '../../domain/usecases/set_feature_flag_override_usecase.dart';
import '../../domain/usecases/list_tenants_usecase.dart';
import '../controllers/feature_flags_controller.dart';
import '../pages/feature_flags_page.dart';

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
