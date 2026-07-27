import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/tenant_config/domain/errors/tenant_config_errors.dart';
import 'package:admin_module/src/features/tenant_config/domain/usecases/tenant_config_usecases.dart';
import 'package:admin_module/src/features/tenant_config/domain/model/tenant_config.dart';
import 'package:admin_module/src/features/tenant_config/domain/parameters/tenant_config_parameters.dart';

import '../../support/fixtures.dart';

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
  group('onUnexpected da feature tenant_config', () {
    test(
      'GetTenantConfigUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = GetTenantConfigUsecase(
          repository:
              _RepoQueLanca<
                TenantConfig,
                GetTenantConfigParameters,
                TenantConfigError
              >(),
        );

        final r = await usecase(
          const GetTenantConfigParameters(tenantId: 't1'),
        );

        expect((r as Failure).error, isA<TenantConfigInesperado>());
      },
    );

    test(
      'UpdateTenantConfigUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = UpdateTenantConfigUsecase(
          repository:
              _RepoQueLanca<
                Unit,
                UpdateTenantConfigParameters,
                TenantConfigError
              >(),
        );

        final r = await usecase(
          UpdateTenantConfigParameters(
            tenantId: 't1',
            config: tenantConfigFixture(),
          ),
        );

        expect((r as Failure).error, isA<TenantConfigInesperado>());
      },
    );
  });
}
