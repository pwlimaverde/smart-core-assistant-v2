import 'package:admin_module/src/features/config/domain/model/plan.dart';
import 'package:admin_module/src/features/config/domain/model/subscription.dart';
import 'package:admin_module/src/features/config/domain/model/payment_record.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/create_plan_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_payments_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_plans_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_subscriptions_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/register_payment_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/update_plan_usecase.dart';
import 'package:admin_module/src/features/config/presentation/controllers/billing_controller.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// O BillingController compoe tres chamadas (planos, assinaturas, pagamentos) num
// unico BillingState via execute(). Um erro em QUALQUER uma delas curto-circuita
// para [Loading, Error]. As acoes de escrita disparam refetch em caso de sucesso.
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUp(() => service = _MockAdminService());

  BillingController build() => BillingController(
        listPlansUsecase: ListPlansUsecase(service: service),
        createPlanUsecase: CreatePlanUsecase(service: service),
        updatePlanUsecase: UpdatePlanUsecase(service: service),
        listSubscriptionsUsecase: ListSubscriptionsUsecase(service: service),
        registerPaymentUsecase: RegisterPaymentUsecase(service: service),
        listPaymentsUsecase: ListPaymentsUsecase(service: service),
      );

  void stubAllOk() {
    when(() => service.listPlans())
        .thenAnswer((_) async => SuccessReturn(success: [planFixture()]));
    when(() => service.listSubscriptions())
        .thenAnswer((_) async => SuccessReturn(success: [subscriptionFixture()]));
    when(() => service.listPayments(tenantId: any(named: 'tenantId')))
        .thenAnswer((_) async => SuccessReturn(success: [paymentRecordFixture()]));
  }

  group('fetchBillingData', () {
    blocTest<BillingController, ViewState<BillingState>>(
      'sucesso: emite [Loading, Success] com plans/subscriptions/payments',
      build: () {
        stubAllOk();
        return build();
      },
      act: (c) => c.fetchBillingData(),
      expect: () => [
        isA<LoadingState<BillingState>>(),
        isA<SuccessState<BillingState>>()
            .having((s) => s.data.plans, 'plans', hasLength(1))
            .having((s) => s.data.subscriptions, 'subscriptions', hasLength(1))
            .having((s) => s.data.payments, 'payments', hasLength(1)),
      ],
    );

    blocTest<BillingController, ViewState<BillingState>>(
      'erro ao listar planos: curto-circuita para [Loading, Error]',
      build: () {
        when(() => service.listPlans())
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchBillingData(),
      expect: () => [
        isA<LoadingState<BillingState>>(),
        isA<ErrorState<BillingState>>(),
      ],
    );

    blocTest<BillingController, ViewState<BillingState>>(
      'erro ao listar assinaturas: curto-circuita para [Loading, Error]',
      build: () {
        when(() => service.listPlans())
            .thenAnswer((_) async => SuccessReturn(success: [planFixture()]));
        when(() => service.listSubscriptions())
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchBillingData(),
      expect: () => [
        isA<LoadingState<BillingState>>(),
        isA<ErrorState<BillingState>>(),
      ],
    );

    blocTest<BillingController, ViewState<BillingState>>(
      'erro ao listar pagamentos: curto-circuita para [Loading, Error]',
      build: () {
        when(() => service.listPlans())
            .thenAnswer((_) async => SuccessReturn(success: [planFixture()]));
        when(() => service.listSubscriptions())
            .thenAnswer((_) async => SuccessReturn(success: [subscriptionFixture()]));
        when(() => service.listPayments(tenantId: any(named: 'tenantId')))
            .thenAnswer((_) async => const ErrorReturn(error: ErrorNetwork()));
        return build();
      },
      act: (c) => c.fetchBillingData(),
      expect: () => [
        isA<LoadingState<BillingState>>(),
        isA<ErrorState<BillingState>>(),
      ],
    );
  });

  group('createPlan', () {
    test('sucesso: dispara refetch e devolve o Plan', () async {
      when(() => service.createPlan(
            name: any(named: 'name'),
            description: any(named: 'description'),
            price: any(named: 'price'),
            maxInstances: any(named: 'maxInstances'),
            maxDepartments: any(named: 'maxDepartments'),
          )).thenAnswer((_) async => SuccessReturn(success: planFixture()));
      stubAllOk();
      final controller = build();

      final res = await controller.createPlan(
          name: 'n', description: 'd', price: '1', maxInstances: 1, maxDepartments: 1);

      expect(res, isA<SuccessReturn<Plan>>());
      verify(() => service.listPlans()).called(1);
      await controller.close();
    });

    test('erro: devolve ErrorReturn sem refetch', () async {
      when(() => service.createPlan(
            name: any(named: 'name'),
            description: any(named: 'description'),
            price: any(named: 'price'),
            maxInstances: any(named: 'maxInstances'),
            maxDepartments: any(named: 'maxDepartments'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorValidation()));
      final controller = build();

      final res = await controller.createPlan(
          name: 'n', description: 'd', price: '1', maxInstances: 1, maxDepartments: 1);

      expect((res as ErrorReturn).result, isA<ErrorValidation>());
      verifyNever(() => service.listPlans());
      await controller.close();
    });
  });

  group('updatePlan', () {
    test('sucesso: dispara refetch', () async {
      when(() => service.updatePlan(
            id: any(named: 'id'),
            name: any(named: 'name'),
            description: any(named: 'description'),
            price: any(named: 'price'),
            maxInstances: any(named: 'maxInstances'),
            maxDepartments: any(named: 'maxDepartments'),
            active: any(named: 'active'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      stubAllOk();
      final controller = build();

      final res = await controller.updatePlan(
          id: 1,
          name: 'n',
          description: 'd',
          price: '1',
          maxInstances: 1,
          maxDepartments: 1,
          active: true);

      expect(res, isA<SuccessReturn<Unit>>());
      verify(() => service.listPlans()).called(1);
      await controller.close();
    });
  });

  group('registerPayment', () {
    test('sucesso: dispara refetch e devolve o PaymentRecord', () async {
      when(() => service.registerPayment(
            tenantId: any(named: 'tenantId'),
            amount: any(named: 'amount'),
            paymentMethod: any(named: 'paymentMethod'),
            paymentDate: any(named: 'paymentDate'),
            periodStart: any(named: 'periodStart'),
            periodEnd: any(named: 'periodEnd'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => SuccessReturn(success: paymentRecordFixture()));
      stubAllOk();
      final controller = build();

      final res = await controller.registerPayment(
          tenantId: 't',
          amount: '1',
          paymentMethod: 'pix',
          paymentDate: 'd',
          periodStart: 's',
          periodEnd: 'e',
          notes: 'n');

      expect(res, isA<SuccessReturn<PaymentRecord>>());
      verify(() => service.listPlans()).called(1);
      await controller.close();
    });

    test('erro: devolve ErrorReturn sem refetch', () async {
      when(() => service.registerPayment(
            tenantId: any(named: 'tenantId'),
            amount: any(named: 'amount'),
            paymentMethod: any(named: 'paymentMethod'),
            paymentDate: any(named: 'paymentDate'),
            periodStart: any(named: 'periodStart'),
            periodEnd: any(named: 'periodEnd'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => const ErrorReturn(error: ErrorValidation()));
      final controller = build();

      final res = await controller.registerPayment(
          tenantId: 't',
          amount: '1',
          paymentMethod: 'pix',
          paymentDate: 'd',
          periodStart: 's',
          periodEnd: 'e',
          notes: 'n');

      expect((res as ErrorReturn).result, isA<ErrorValidation>());
      verifyNever(() => service.listPlans());
      await controller.close();
    });
  });

  // BillingState.copyWith preserva os campos nao informados e substitui os demais.
  group('BillingState.copyWith', () {
    test('substitui apenas os campos informados', () {
      final base = BillingState(
        plans: [planFixture(id: 1)],
        subscriptions: const <Subscription>[],
        payments: const <PaymentRecord>[],
      );
      final novo = base.copyWith(plans: [planFixture(id: 2)]);
      expect(novo.plans.single.id, 2);
      expect(novo.subscriptions, same(base.subscriptions));
      expect(novo.payments, same(base.payments));
    });

    test('sem argumentos preserva todos os campos originais', () {
      final base = BillingState(
        plans: [planFixture(id: 1)],
        subscriptions: [subscriptionFixture()],
        payments: [paymentRecordFixture()],
      );
      final copia = base.copyWith();
      expect(copia.plans, same(base.plans));
      expect(copia.subscriptions, same(base.subscriptions));
      expect(copia.payments, same(base.payments));
    });
  });
}
