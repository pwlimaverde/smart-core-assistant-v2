import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/billing/domain/errors/billing_errors.dart';
import 'package:admin_module/src/features/billing/domain/usecases/billing_usecases.dart';
import 'package:admin_module/src/features/billing/domain/model/plan.dart';
import 'package:admin_module/src/features/billing/domain/model/subscription.dart';
import 'package:admin_module/src/features/billing/domain/model/payment_record.dart';
import 'package:admin_module/src/features/billing/domain/parameters/billing_parameters.dart';

/// Repositório que quebra o contrato: lança em vez de devolver `Failure`.
///
/// A base do usecase protege o chamador disso convertendo via
/// `onUnexpected` — é a garantia central da lib, e a única forma de
/// exercitá-la é com uma implementação manual fora do contrato.
final class _RepoQueLanca<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    throw StateError('repositorio fora do contrato');
  }
}

void main() {
  group('onUnexpected da feature billing', () {
    test(
      'ListPlansUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ListPlansUsecase(
          repository: _RepoQueLanca<List<Plan>, NoParams, BillingError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<BillingInesperado>());
      },
    );

    test(
      'CreatePlanUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = CreatePlanUsecase(
          repository: _RepoQueLanca<Plan, CreatePlanParameters, BillingError>(),
        );

        final r = await usecase(
          const CreatePlanParameters(
            name: 'n',
            description: 'd',
            price: '1',
            maxInstances: 1,
            maxDepartments: 1,
            maxFluxos: 1,
          ),
        );

        expect((r as Failure).error, isA<BillingInesperado>());
      },
    );

    test(
      'UpdatePlanUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = UpdatePlanUsecase(
          repository: _RepoQueLanca<Unit, UpdatePlanParameters, BillingError>(),
        );

        final r = await usecase(
          const UpdatePlanParameters(
            id: 1,
            name: 'n',
            description: 'd',
            price: '1',
            maxInstances: 1,
            maxDepartments: 1,
            maxFluxos: 1,
            active: true,
          ),
        );

        expect((r as Failure).error, isA<BillingInesperado>());
      },
    );

    test(
      'ListSubscriptionsUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ListSubscriptionsUsecase(
          repository:
              _RepoQueLanca<List<Subscription>, NoParams, BillingError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<BillingInesperado>());
      },
    );

    test(
      'RegisterPaymentUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = RegisterPaymentUsecase(
          repository:
              _RepoQueLanca<
                PaymentRecord,
                RegisterPaymentParameters,
                BillingError
              >(),
        );

        final r = await usecase(
          const RegisterPaymentParameters(
            tenantId: 't1',
            amount: '1',
            paymentMethod: 'pix',
            paymentDate: 'd',
            periodStart: 'a',
            periodEnd: 'b',
            notes: '',
          ),
        );

        expect((r as Failure).error, isA<BillingInesperado>());
      },
    );

    test(
      'ListPaymentsUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ListPaymentsUsecase(
          repository:
              _RepoQueLanca<
                List<PaymentRecord>,
                ListPaymentsParameters,
                BillingError
              >(),
        );

        final r = await usecase(const ListPaymentsParameters());

        expect((r as Failure).error, isA<BillingInesperado>());
      },
    );
  });
}
