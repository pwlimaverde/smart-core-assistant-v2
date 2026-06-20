import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class GenerateAccessCodeUsecase {
  final AdminService _service;

  const GenerateAccessCodeUsecase({required this._service});

  Future<ReturnSuccessOrError<String>> call(String id) => _service.generateAccessCode(id);
}
