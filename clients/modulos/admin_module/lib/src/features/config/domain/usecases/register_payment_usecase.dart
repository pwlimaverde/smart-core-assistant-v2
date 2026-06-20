import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/payment_record.dart';
import '../services/admin_service.dart';

final class RegisterPaymentUsecase {
  final AdminService _service;

  const RegisterPaymentUsecase({required this._service});

  Future<ReturnSuccessOrError<PaymentRecord>> call({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  }) =>
      _service.registerPayment(
        tenantId: tenantId,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentDate: paymentDate,
        periodStart: periodStart,
        periodEnd: periodEnd,
        notes: notes,
      );
}
