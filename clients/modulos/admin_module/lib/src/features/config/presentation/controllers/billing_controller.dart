import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/model/payment_record.dart';
import '../../domain/usecases/list_plans_usecase.dart';
import '../../domain/usecases/create_plan_usecase.dart';
import '../../domain/usecases/update_plan_usecase.dart';
import '../../domain/usecases/list_subscriptions_usecase.dart';
import '../../domain/usecases/register_payment_usecase.dart';
import '../../domain/usecases/list_payments_usecase.dart';

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

  Future<void> fetchBillingData() async {
    await execute(() async {
      final plansRes = await _listPlansUsecase.call();
      if (plansRes is ErrorReturn<List<Plan>>) {
        return ErrorReturn(error: plansRes.result);
      }

      final subsRes = await _listSubscriptionsUsecase.call();
      if (subsRes is ErrorReturn<List<Subscription>>) {
        return ErrorReturn(error: subsRes.result);
      }

      final paymentsRes = await _listPaymentsUsecase.call();
      if (paymentsRes is ErrorReturn<List<PaymentRecord>>) {
        return ErrorReturn(error: paymentsRes.result);
      }

      return SuccessReturn(
        success: BillingState(
          plans: (plansRes as SuccessReturn<List<Plan>>).result,
          subscriptions: (subsRes as SuccessReturn<List<Subscription>>).result,
          payments: (paymentsRes as SuccessReturn<List<PaymentRecord>>).result,
        ),
      );
    });
  }

  Future<ReturnSuccessOrError<Plan>> createPlan({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  }) async {
    final res = await _createPlanUsecase.call(
      name: name,
      description: description,
      price: price,
      maxInstances: maxInstances,
      maxDepartments: maxDepartments,
    );
    if (res is SuccessReturn<Plan>) {
      await fetchBillingData();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit>> updatePlan({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  }) async {
    final res = await _updatePlanUsecase.call(
      id: id,
      name: name,
      description: description,
      price: price,
      maxInstances: maxInstances,
      maxDepartments: maxDepartments,
      active: active,
    );
    if (res is SuccessReturn<Unit>) {
      await fetchBillingData();
    }
    return res;
  }

  Future<ReturnSuccessOrError<PaymentRecord>> registerPayment({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  }) async {
    final res = await _registerPaymentUsecase.call(
      tenantId: tenantId,
      amount: amount,
      paymentMethod: paymentMethod,
      paymentDate: paymentDate,
      periodStart: periodStart,
      periodEnd: periodEnd,
      notes: notes,
    );
    if (res is SuccessReturn<PaymentRecord>) {
      await fetchBillingData();
    }
    return res;
  }
}
