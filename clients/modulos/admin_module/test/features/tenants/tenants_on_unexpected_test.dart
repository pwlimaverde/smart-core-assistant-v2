import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/tenants/domain/errors/tenants_errors.dart';
import 'package:admin_module/src/features/tenants/domain/usecases/tenants_usecases.dart';
import 'package:admin_module/src/features/tenants/domain/model/tenant.dart';
import 'package:admin_module/src/features/tenants/domain/parameters/tenants_parameters.dart';

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
  group('onUnexpected da feature tenants', () {
    test(
      'ListTenantsUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ListTenantsUsecase(
          repository: _RepoQueLanca<List<Tenant>, NoParams, TenantsError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );

    test(
      'GetTenantUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = GetTenantUsecase(
          repository:
              _RepoQueLanca<Tenant, GetTenantParameters, TenantsError>(),
        );

        final r = await usecase(const GetTenantParameters(id: 't1'));

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );

    test(
      'CreateTenantUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = CreateTenantUsecase(
          repository:
              _RepoQueLanca<Tenant, CreateTenantParameters, TenantsError>(),
        );

        final r = await usecase(
          const CreateTenantParameters(
            name: 'n',
            slug: 's',
            ownerId: 1,
            email: 'e@e.com',
            phone: '1',
          ),
        );

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );

    test(
      'UpdateTenantUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = UpdateTenantUsecase(
          repository:
              _RepoQueLanca<Unit, UpdateTenantParameters, TenantsError>(),
        );

        final r = await usecase(
          const UpdateTenantParameters(
            id: 't1',
            name: 'n',
            slug: 's',
            ownerId: 1,
            email: 'e@e.com',
            phone: '1',
          ),
        );

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );

    test(
      'SetTenantActiveUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = SetTenantActiveUsecase(
          repository:
              _RepoQueLanca<Unit, SetTenantActiveParameters, TenantsError>(),
        );

        final r = await usecase(
          const SetTenantActiveParameters(id: 't1', active: true),
        );

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );

    test(
      'GenerateAccessCodeUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = GenerateAccessCodeUsecase(
          repository:
              _RepoQueLanca<
                String,
                GenerateAccessCodeParameters,
                TenantsError
              >(),
        );

        final r = await usecase(const GenerateAccessCodeParameters(id: 't1'));

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );

    test(
      'ExportTenantsCsvUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ExportTenantsCsvUsecase(
          repository: _RepoQueLanca<List<int>, NoParams, TenantsError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<TenantsInesperado>());
      },
    );
  });
}
