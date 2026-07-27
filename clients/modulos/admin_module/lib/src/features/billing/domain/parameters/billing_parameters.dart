import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações da feature `billing`.
///
/// Um `Parameters` por operação: é ele que atravessa as três camadas e chega
/// ao `mapError` como contexto da falha.
/// Cria um plano.
final class CreatePlanParameters extends Parameters {
  final String name;
  final String description;
  final String price;
  final int maxInstances;
  final int maxDepartments;

  const CreatePlanParameters({
    required this.name,
    required this.description,
    required this.price,
    required this.maxInstances,
    required this.maxDepartments,
  });
}

/// Atualiza um plano.
final class UpdatePlanParameters extends Parameters {
  final int id;
  final String name;
  final String description;
  final String price;
  final int maxInstances;
  final int maxDepartments;
  final bool active;

  const UpdatePlanParameters({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.maxInstances,
    required this.maxDepartments,
    required this.active,
  });
}

/// Registra um pagamento recebido.
final class RegisterPaymentParameters extends Parameters {
  final String tenantId;
  final String amount;
  final String paymentMethod;
  final String paymentDate;
  final String periodStart;
  final String periodEnd;
  final String notes;

  const RegisterPaymentParameters({
    required this.tenantId,
    required this.amount,
    required this.paymentMethod,
    required this.paymentDate,
    required this.periodStart,
    required this.periodEnd,
    required this.notes,
  });
}

/// Lista pagamentos (todos ou de um tenant).
final class ListPaymentsParameters extends Parameters {
  final String? tenantId;

  const ListPaymentsParameters({this.tenantId});
}
