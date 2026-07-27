import 'package:meta/meta.dart';

@immutable
class PaymentRecord {
  final int id;
  final String tenantId;
  final String amount;
  final String paymentDate;
  final String paymentMethod;
  final String periodStart;
  final String periodEnd;
  final String notes;
  final int recordedById;
  final DateTime createdAt;

  const PaymentRecord({
    required this.id,
    required this.tenantId,
    required this.amount,
    required this.paymentDate,
    required this.paymentMethod,
    required this.periodStart,
    required this.periodEnd,
    required this.notes,
    required this.recordedById,
    required this.createdAt,
  });
}
