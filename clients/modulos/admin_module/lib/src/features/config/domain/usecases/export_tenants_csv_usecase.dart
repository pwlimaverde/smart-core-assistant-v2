import 'package:return_success_or_error/return_success_or_error.dart';

import '../services/admin_service.dart';

final class ExportTenantsCsvUsecase {
  final AdminService _service;

  const ExportTenantsCsvUsecase({required this._service});

  Future<ReturnSuccessOrError<List<int>>> call() => _service.exportTenantsCsv();
}
