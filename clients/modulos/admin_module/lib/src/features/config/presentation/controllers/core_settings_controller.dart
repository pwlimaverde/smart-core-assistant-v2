import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/core_setting.dart';
import '../../domain/usecases/list_core_settings_usecase.dart';
import '../../domain/usecases/upsert_core_setting_usecase.dart';
import '../../domain/usecases/delete_core_setting_usecase.dart';

final class CoreSettingsController extends BaseController<List<CoreSetting>> {
  final ListCoreSettingsUsecase _listUsecase;
  final UpsertCoreSettingUsecase _upsertUsecase;
  final DeleteCoreSettingUsecase _deleteUsecase;

  CoreSettingsController({
    required this._listUsecase,
    required this._upsertUsecase,
    required this._deleteUsecase,
  });

  Future<void> fetchSettings() => execute(() => _listUsecase.call());

  Future<ReturnSuccessOrError<Unit>> upsertSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  }) async {
    final res = await _upsertUsecase.call(
      key: key,
      value: value,
      encrypted: encrypted,
      description: description,
    );
    if (res is SuccessReturn<Unit>) {
      await fetchSettings();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit>> deleteSetting(String key) async {
    final res = await _deleteUsecase.call(key);
    if (res is SuccessReturn<Unit>) {
      await fetchSettings();
    }
    return res;
  }
}
