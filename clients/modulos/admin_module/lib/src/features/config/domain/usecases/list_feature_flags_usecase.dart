import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/feature_flag.dart';
import '../services/admin_service.dart';

final class ListFeatureFlagsUsecase {
  final AdminService _service;

  const ListFeatureFlagsUsecase({required this._service});

  Future<ReturnSuccessOrError<List<FeatureFlag>>> call() => _service.listFeatureFlags();
}
