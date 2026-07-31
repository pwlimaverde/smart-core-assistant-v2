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

// --- Vouchers de ativação ---

/// Cria um voucher.
final class CreateVoucherParameters extends Parameters {
  final String codigo;
  final String descricao;
  final int planId;
  final int duracaoDias;

  /// 0 = ilimitado.
  final int maxResgates;

  /// RFC 3339; vazio = sem expiração.
  final String validoAte;

  const CreateVoucherParameters({
    required this.codigo,
    required this.descricao,
    required this.planId,
    required this.duracaoDias,
    required this.maxResgates,
    this.validoAte = '',
  });
}

/// Revoga um voucher: bloqueia novos resgates e **preserva** as assinaturas já
/// concedidas — revogar um código não rescinde contrato firmado.
final class RevokeVoucherParameters extends Parameters {
  final String voucherId;
  final String motivo;

  const RevokeVoucherParameters({
    required this.voucherId,
    required this.motivo,
  });
}

/// Histórico de resgates de um voucher.
final class VoucherRedemptionsParameters extends Parameters {
  final String voucherId;

  const VoucherRedemptionsParameters({required this.voucherId});
}
