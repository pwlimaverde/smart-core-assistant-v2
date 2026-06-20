import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/list_core_settings_usecase.dart';
import '../../domain/usecases/upsert_core_setting_usecase.dart';
import '../../domain/usecases/delete_core_setting_usecase.dart';
import '../controllers/core_settings_controller.dart';
import '../pages/core_settings_page.dart';

final class CoreSettingsRoute extends GetItModule {
  @override
  String get path => '/admin/core-settings';

  @override
  Widget get page => const CoreSettingsPage();

  @override
  void binds(Injector i) {
    i.controller<CoreSettingsController>(
      () => CoreSettingsController(
        listUsecase: inject<ListCoreSettingsUsecase>(),
        upsertUsecase: inject<UpsertCoreSettingUsecase>(),
        deleteUsecase: inject<DeleteCoreSettingUsecase>(),
      ),
    );
  }
}
