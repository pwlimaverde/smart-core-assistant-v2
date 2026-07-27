import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/tenants_errors.dart';
import '../../domain/model/tenant.dart';
import '../../domain/parameters/tenants_parameters.dart';

/// Fronteiras da feature `tenants`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

TenantsError _mapTenants(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.tenants',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const TenantsAcessoNegado(),
    GrpcFailureKind.notFound => const TenantsNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const TenantsConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const TenantsDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const TenantsIndisponivel(),
    GrpcFailureKind.unknown => const TenantsInesperado(),
  };
}

final class ListTenantsRepository
    extends RepositoryBase<List<Tenant>, NoParams, TenantsError> {
  const ListTenantsRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapTenants('listTenants', exception, stackTrace);
}

final class GetTenantRepository
    extends RepositoryBase<Tenant, GetTenantParameters, TenantsError> {
  const GetTenantRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    GetTenantParameters parameters,
  ) => _mapTenants('getTenant', exception, stackTrace);
}

final class CreateTenantRepository
    extends RepositoryBase<Tenant, CreateTenantParameters, TenantsError> {
  const CreateTenantRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    CreateTenantParameters parameters,
  ) => _mapTenants('createTenant', exception, stackTrace);
}

final class UpdateTenantRepository
    extends RepositoryBase<Unit, UpdateTenantParameters, TenantsError> {
  const UpdateTenantRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    UpdateTenantParameters parameters,
  ) => _mapTenants('updateTenant', exception, stackTrace);
}

final class SetTenantActiveRepository
    extends RepositoryBase<Unit, SetTenantActiveParameters, TenantsError> {
  const SetTenantActiveRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    SetTenantActiveParameters parameters,
  ) => _mapTenants('setTenantActive', exception, stackTrace);
}

final class GenerateAccessCodeRepository
    extends RepositoryBase<String, GenerateAccessCodeParameters, TenantsError> {
  const GenerateAccessCodeRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    GenerateAccessCodeParameters parameters,
  ) => _mapTenants('generateAccessCode', exception, stackTrace);
}

final class ExportTenantsCsvRepository
    extends RepositoryBase<List<int>, NoParams, TenantsError> {
  const ExportTenantsCsvRepository({required super.datasource});

  @override
  TenantsError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapTenants('exportTenantsCsv', exception, stackTrace);
}
