import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/core_settings_errors.dart';
import '../../domain/usecases/core_settings_usecases.dart';
import '../../domain/parameters/core_settings_parameters.dart';
import '../../domain/model/core_setting.dart';

final class CoreSettingsController extends BaseController<List<CoreSetting>> {
  final ListCoreSettingsUsecase _listUsecase;
  final UpsertCoreSettingUsecase _upsertUsecase;
  final DeleteCoreSettingUsecase _deleteUsecase;

  CoreSettingsController({
    required this._listUsecase,
    required this._upsertUsecase,
    required this._deleteUsecase,
  });

  Future<void> fetchSettings() => execute(() => _listUsecase(noParams));

  Future<ReturnSuccessOrError<Unit, CoreSettingsError>> upsertSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  }) async {
    final res = await _upsertUsecase(
      UpsertCoreSettingParameters(
        key: key,
        value: value,
        encrypted: encrypted,
        description: description,
      ),
    );
    if (res is Success) {
      await fetchSettings();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit, CoreSettingsError>> deleteSetting(
    String key,
  ) async {
    final res = await _deleteUsecase(DeleteCoreSettingParameters(key: key));
    if (res is Success) {
      await fetchSettings();
    }
    return res;
  }
}
