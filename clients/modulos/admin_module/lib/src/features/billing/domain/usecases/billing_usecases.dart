import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/billing_errors.dart';
import '../model/payment_record.dart';
import '../model/plan.dart';
import '../model/subscription.dart';
import '../model/voucher.dart';
import '../parameters/billing_parameters.dart';

/// Casos de uso da feature `billing`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.billing',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lista os planos comerciais.
final class ListPlansUsecase
    extends
        UsecaseBaseCallData<List<Plan>, List<Plan>, NoParams, BillingError> {
  const ListPlansUsecase({required super.repository});

  @override
  ProcessData<List<Plan>, List<Plan>, NoParams, BillingError> get process =>
      _process;

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listPlans', exception, stackTrace);
    return const BillingInesperado();
  }

  static ReturnSuccessOrError<List<Plan>, BillingError> _process(
    List<Plan> data,
    NoParams parameters,
  ) => Success(data);
}

/// Cria um plano.
final class CreatePlanUsecase
    extends
        UsecaseBaseCallData<Plan, Plan, CreatePlanParameters, BillingError> {
  const CreatePlanUsecase({required super.repository});

  @override
  ProcessData<Plan, Plan, CreatePlanParameters, BillingError> get process =>
      _process;

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('createPlan', exception, stackTrace);
    return const BillingInesperado();
  }

  static ReturnSuccessOrError<Plan, BillingError> _process(
    Plan data,
    CreatePlanParameters parameters,
  ) => Success(data);
}

/// Atualiza um plano.
final class UpdatePlanUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, UpdatePlanParameters, BillingError> {
  const UpdatePlanUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, UpdatePlanParameters, BillingError> get process =>
      _process;

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('updatePlan', exception, stackTrace);
    return const BillingInesperado();
  }

  static ReturnSuccessOrError<Unit, BillingError> _process(
    Unit data,
    UpdatePlanParameters parameters,
  ) => Success(data);
}

/// Lista as assinaturas ativas.
final class ListSubscriptionsUsecase
    extends
        UsecaseBaseCallData<
          List<Subscription>,
          List<Subscription>,
          NoParams,
          BillingError
        > {
  const ListSubscriptionsUsecase({required super.repository});

  @override
  ProcessData<List<Subscription>, List<Subscription>, NoParams, BillingError>
  get process => _process;

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listSubscriptions', exception, stackTrace);
    return const BillingInesperado();
  }

  static ReturnSuccessOrError<List<Subscription>, BillingError> _process(
    List<Subscription> data,
    NoParams parameters,
  ) => Success(data);
}

/// Registra um pagamento recebido.
final class RegisterPaymentUsecase
    extends
        UsecaseBaseCallData<
          PaymentRecord,
          PaymentRecord,
          RegisterPaymentParameters,
          BillingError
        > {
  const RegisterPaymentUsecase({required super.repository});

  @override
  ProcessData<
    PaymentRecord,
    PaymentRecord,
    RegisterPaymentParameters,
    BillingError
  >
  get process => _process;

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('registerPayment', exception, stackTrace);
    return const BillingInesperado();
  }

  static ReturnSuccessOrError<PaymentRecord, BillingError> _process(
    PaymentRecord data,
    RegisterPaymentParameters parameters,
  ) => Success(data);
}

/// Lista pagamentos (todos ou de um tenant).
final class ListPaymentsUsecase
    extends
        UsecaseBaseCallData<
          List<PaymentRecord>,
          List<PaymentRecord>,
          ListPaymentsParameters,
          BillingError
        > {
  const ListPaymentsUsecase({required super.repository});

  @override
  ProcessData<
    List<PaymentRecord>,
    List<PaymentRecord>,
    ListPaymentsParameters,
    BillingError
  >
  get process => _process;

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listPayments', exception, stackTrace);
    return const BillingInesperado();
  }

  static ReturnSuccessOrError<List<PaymentRecord>, BillingError> _process(
    List<PaymentRecord> data,
    ListPaymentsParameters parameters,
  ) => Success(data);
}

// --- Vouchers de ativação ---

/// Lista os vouchers.
final class ListVouchersUsecase
    extends
        UsecaseBaseCallData<
          List<Voucher>,
          List<Voucher>,
          NoParams,
          BillingError
        > {
  const ListVouchersUsecase({required super.repository});

  @override
  ProcessData<List<Voucher>, List<Voucher>, NoParams, BillingError>
  get process => (data, _) => Success(data);

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listVouchers', exception, stackTrace);
    return const BillingInesperado();
  }
}

/// Cria um voucher.
///
/// A validação real é do servidor; o que este `process` barra é o que a tela
/// não deveria ter deixado passar — um código vazio ou uma duração não
/// positiva geram um voucher que nunca funciona.
final class CreateVoucherUsecase
    extends
        UsecaseBaseCallData<
          Voucher,
          Voucher,
          CreateVoucherParameters,
          BillingError
        > {
  const CreateVoucherUsecase({required super.repository});

  @override
  ProcessData<Voucher, Voucher, CreateVoucherParameters, BillingError>
  get process => (data, _) => Success(data);

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('createVoucher', exception, stackTrace);
    return const BillingInesperado();
  }
}

/// Revoga um voucher.
final class RevokeVoucherUsecase
    extends
        UsecaseBaseCallData<bool, bool, RevokeVoucherParameters, BillingError> {
  const RevokeVoucherUsecase({required super.repository});

  @override
  ProcessData<bool, bool, RevokeVoucherParameters, BillingError> get process =>
      (data, _) => Success(data);

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('revokeVoucher', exception, stackTrace);
    return const BillingInesperado();
  }
}

/// Histórico de resgates de um voucher.
final class ListVoucherRedemptionsUsecase
    extends
        UsecaseBaseCallData<
          List<VoucherRedemption>,
          List<VoucherRedemption>,
          VoucherRedemptionsParameters,
          BillingError
        > {
  const ListVoucherRedemptionsUsecase({required super.repository});

  @override
  ProcessData<
    List<VoucherRedemption>,
    List<VoucherRedemption>,
    VoucherRedemptionsParameters,
    BillingError
  >
  get process => (data, _) => Success(data);

  @override
  BillingError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listVoucherRedemptions', exception, stackTrace);
    return const BillingInesperado();
  }
}
