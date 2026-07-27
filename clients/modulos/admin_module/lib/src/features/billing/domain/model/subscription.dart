import 'package:meta/meta.dart';

@immutable
class Subscription {
  final int id;
  final String tenantId;
  final int planId;
  final String status;
  final DateTime currentPeriodStart;
  final DateTime currentPeriodEnd;
  final String paymentGateway;
  final String externalCustomerId;
  final String externalSubscriptionId;
  final DateTime updatedAt;

  const Subscription({
    required this.id,
    required this.tenantId,
    required this.planId,
    required this.status,
    required this.currentPeriodStart,
    required this.currentPeriodEnd,
    required this.paymentGateway,
    required this.externalCustomerId,
    required this.externalSubscriptionId,
    required this.updatedAt,
  });
}
