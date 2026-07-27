import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/billing_errors.dart';
import '../../domain/usecases/billing_usecases.dart';
import '../../domain/parameters/billing_parameters.dart';
import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/model/payment_record.dart';

class BillingState {
  final List<Plan> plans;
  final List<Subscription> subscriptions;
  final List<PaymentRecord> payments;

  BillingState({
    required this.plans,
    required this.subscriptions,
    required this.payments,
  });

  BillingState copyWith({
    List<Plan>? plans,
    List<Subscription>? subscriptions,
    List<PaymentRecord>? payments,
  }) {
    return BillingState(
      plans: plans ?? this.plans,
      subscriptions: subscriptions ?? this.subscriptions,
      payments: payments ?? this.payments,
    );
  }
}

final class BillingController extends BaseController<BillingState> {
  final ListPlansUsecase _listPlansUsecase;
  final CreatePlanUsecase _createPlanUsecase;
  final UpdatePlanUsecase _updatePlanUsecase;
  final ListSubscriptionsUsecase _listSubscriptionsUsecase;
  final RegisterPaymentUsecase _registerPaymentUsecase;
  final ListPaymentsUsecase _listPaymentsUsecase;

  BillingController({
    required this._listPlansUsecase,
    required this._createPlanUsecase,
    required this._updatePlanUsecase,
    required this._listSubscriptionsUsecase,
    required this._registerPaymentUsecase,
    required this._listPaymentsUsecase,
  });

  /// Carrega planos, assinaturas e pagamentos numa única passada.
  ///
  /// Curto-circuita na primeira falha: a tela de cobrança não faz sentido com
  /// dados parciais, e reconstruir o `Failure` com o erro recebido preserva o
  /// caso concreto para o `ErrorMessageMapper`.
  Future<void> fetchBillingData() async {
    await execute(() async {
      final plansRes = await _listPlansUsecase(noParams);
      if (plansRes case Failure(:final error)) {
        return Failure<BillingState, BillingError>(error);
      }

      final subsRes = await _listSubscriptionsUsecase(noParams);
      if (subsRes case Failure(:final error)) {
        return Failure<BillingState, BillingError>(error);
      }

      final paymentsRes = await _listPaymentsUsecase(
        const ListPaymentsParameters(),
      );
      if (paymentsRes case Failure(:final error)) {
        return Failure<BillingState, BillingError>(error);
      }

      return Success<BillingState, BillingError>(
        BillingState(
          plans: (plansRes as Success<List<Plan>, BillingError>).value,
          subscriptions:
              (subsRes as Success<List<Subscription>, BillingError>).value,
          payments:
              (paymentsRes as Success<List<PaymentRecord>, BillingError>).value,
        ),
      );
    });
  }

  Future<ReturnSuccessOrError<Plan, BillingError>> createPlan({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  }) async {
    final res = await _createPlanUsecase(
      CreatePlanParameters(
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
      ),
    );
    if (res is Success) {
      await fetchBillingData();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit, BillingError>> updatePlan({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  }) async {
    final res = await _updatePlanUsecase(
      UpdatePlanParameters(
        id: id,
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
        active: active,
      ),
    );
    if (res is Success) {
      await fetchBillingData();
    }
    return res;
  }

  Future<ReturnSuccessOrError<PaymentRecord, BillingError>> registerPayment({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  }) async {
    final res = await _registerPaymentUsecase(
      RegisterPaymentParameters(
        tenantId: tenantId,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentDate: paymentDate,
        periodStart: periodStart,
        periodEnd: periodEnd,
        notes: notes,
      ),
    );
    if (res is Success) {
      await fetchBillingData();
    }
    return res;
  }
}
