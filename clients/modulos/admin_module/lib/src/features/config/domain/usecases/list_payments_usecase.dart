import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/payment_record.dart';
import '../services/admin_service.dart';

final class ListPaymentsUsecase {
  final AdminService _service;

  const ListPaymentsUsecase({required this._service});

  Future<ReturnSuccessOrError<List<PaymentRecord>>> call({String? tenantId}) =>
      _service.listPayments(tenantId: tenantId);
}
