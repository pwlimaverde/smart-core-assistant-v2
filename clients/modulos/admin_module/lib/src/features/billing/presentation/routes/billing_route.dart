import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/billing_controller.dart';
import '../pages/billing_page.dart';
import '../../domain/usecases/billing_usecases.dart';

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
        listVouchersUsecase: inject<ListVouchersUsecase>(),
        createVoucherUsecase: inject<CreateVoucherUsecase>(),
        revokeVoucherUsecase: inject<RevokeVoucherUsecase>(),
        listVoucherRedemptionsUsecase: inject<ListVoucherRedemptionsUsecase>(),
      ),
    );
  }
}
