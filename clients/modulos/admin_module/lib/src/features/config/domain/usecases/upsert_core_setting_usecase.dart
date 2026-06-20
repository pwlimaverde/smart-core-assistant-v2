import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class UpsertCoreSettingUsecase {
  final AdminService _service;

  const UpsertCoreSettingUsecase({required this._service});

  Future<ReturnSuccessOrError<Unit>> call({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  }) =>
      _service.upsertCoreSetting(
        key: key,
        value: value,
        encrypted: encrypted,
        description: description,
      );
}
