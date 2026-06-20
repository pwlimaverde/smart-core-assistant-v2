import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/core_setting.dart';
import '../services/admin_service.dart';

final class ListCoreSettingsUsecase {
  final AdminService _service;

  const ListCoreSettingsUsecase({required this._service});

  Future<ReturnSuccessOrError<List<CoreSetting>>> call() => _service.listCoreSettings();
}
