import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/billing_errors.dart';
import '../../domain/model/payment_record.dart';
import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/parameters/billing_parameters.dart';

/// Fronteiras da feature `billing`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

BillingError _mapBilling(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.billing',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const BillingAcessoNegado(),
    GrpcFailureKind.notFound => const BillingNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const BillingConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const BillingDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const BillingIndisponivel(),
    GrpcFailureKind.unknown => const BillingInesperado(),
  };
}

final class ListPlansRepository
    extends RepositoryBase<List<Plan>, NoParams, BillingError> {
  const ListPlansRepository({required super.datasource});

  @override
  BillingError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapBilling('listPlans', exception, stackTrace);
}

final class CreatePlanRepository
    extends RepositoryBase<Plan, CreatePlanParameters, BillingError> {
  const CreatePlanRepository({required super.datasource});

  @override
  BillingError mapError(
    Object exception,
    StackTrace stackTrace,
    CreatePlanParameters parameters,
  ) => _mapBilling('createPlan', exception, stackTrace);
}

final class UpdatePlanRepository
    extends RepositoryBase<Unit, UpdatePlanParameters, BillingError> {
  const UpdatePlanRepository({required super.datasource});

  @override
  BillingError mapError(
    Object exception,
    StackTrace stackTrace,
    UpdatePlanParameters parameters,
  ) => _mapBilling('updatePlan', exception, stackTrace);
}

final class ListSubscriptionsRepository
    extends RepositoryBase<List<Subscription>, NoParams, BillingError> {
  const ListSubscriptionsRepository({required super.datasource});

  @override
  BillingError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapBilling('listSubscriptions', exception, stackTrace);
}

final class RegisterPaymentRepository
    extends
        RepositoryBase<PaymentRecord, RegisterPaymentParameters, BillingError> {
  const RegisterPaymentRepository({required super.datasource});

  @override
  BillingError mapError(
    Object exception,
    StackTrace stackTrace,
    RegisterPaymentParameters parameters,
  ) => _mapBilling('registerPayment', exception, stackTrace);
}

final class ListPaymentsRepository
    extends
        RepositoryBase<
          List<PaymentRecord>,
          ListPaymentsParameters,
          BillingError
        > {
  const ListPaymentsRepository({required super.datasource});

  @override
  BillingError mapError(
    Object exception,
    StackTrace stackTrace,
    ListPaymentsParameters parameters,
  ) => _mapBilling('listPayments', exception, stackTrace);
}
