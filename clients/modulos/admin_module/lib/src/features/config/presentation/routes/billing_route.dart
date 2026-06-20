import 'package:dependencies_module/dependencies_module.dart';

import '../../domain/usecases/list_plans_usecase.dart';
import '../../domain/usecases/create_plan_usecase.dart';
import '../../domain/usecases/update_plan_usecase.dart';
import '../../domain/usecases/list_subscriptions_usecase.dart';
import '../../domain/usecases/register_payment_usecase.dart';
import '../../domain/usecases/list_payments_usecase.dart';
import '../controllers/billing_controller.dart';
import '../pages/billing_page.dart';

final class BillingRoute extends GetItModule {
  @override
  String get path => '/admin/billing';

  @override
  Widget get page => const BillingPage();

  @override
  void binds(Injector i) {
    i.controller<BillingController>(
      () => BillingController(
        listPlansUsecase: inject<ListPlansUsecase>(),
        createPlanUsecase: inject<CreatePlanUsecase>(),
        updatePlanUsecase: inject<UpdatePlanUsecase>(),
        listSubscriptionsUsecase: inject<ListSubscriptionsUsecase>(),
        registerPaymentUsecase: inject<RegisterPaymentUsecase>(),
        listPaymentsUsecase: inject<ListPaymentsUsecase>(),
      ),
    );
  }
}
