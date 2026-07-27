import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/dashboard/domain/errors/dashboard_errors.dart';
import 'package:admin_module/src/features/dashboard/domain/usecases/dashboard_usecases.dart';
import 'package:admin_module/src/features/dashboard/domain/model/service_health.dart';
import 'package:admin_module/src/features/dashboard/domain/model/dashboard_summary.dart';

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
  group('onUnexpected da feature dashboard', () {
    test(
      'GetServiceHealthUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = GetServiceHealthUsecase(
          repository:
              _RepoQueLanca<List<ServiceHealth>, NoParams, DashboardError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<DashboardInesperado>());
      },
    );

    test(
      'GetDashboardSummaryUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = GetDashboardSummaryUsecase(
          repository:
              _RepoQueLanca<DashboardSummary, NoParams, DashboardError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<DashboardInesperado>());
      },
    );
  });
}
