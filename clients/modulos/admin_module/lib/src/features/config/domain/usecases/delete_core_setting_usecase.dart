import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class DeleteCoreSettingUsecase {
  final AdminService _service;

  const DeleteCoreSettingUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call(String key) => _service.deleteCoreSetting(key);
}
