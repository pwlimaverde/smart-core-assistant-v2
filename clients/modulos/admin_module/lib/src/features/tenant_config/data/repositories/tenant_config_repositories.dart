import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/tenant_config_errors.dart';
import '../../domain/model/tenant_config.dart';
import '../../domain/parameters/tenant_config_parameters.dart';

/// Fronteiras da feature `tenant_config`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

TenantConfigError _mapTenantConfig(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.tenant_config',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const TenantConfigAcessoNegado(),
    GrpcFailureKind.notFound => const TenantConfigNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const TenantConfigConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const TenantConfigDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const TenantConfigIndisponivel(),
    GrpcFailureKind.unknown => const TenantConfigInesperado(),
  };
}

final class GetTenantConfigRepository
    extends
        RepositoryBase<
          TenantConfig,
          GetTenantConfigParameters,
          TenantConfigError
        > {
  const GetTenantConfigRepository({required super.datasource});

  @override
  TenantConfigError mapError(
    Object exception,
    StackTrace stackTrace,
    GetTenantConfigParameters parameters,
  ) => _mapTenantConfig('getTenantConfig', exception, stackTrace);
}

final class UpdateTenantConfigRepository
    extends
        RepositoryBase<Unit, UpdateTenantConfigParameters, TenantConfigError> {
  const UpdateTenantConfigRepository({required super.datasource});

  @override
  TenantConfigError mapError(
    Object exception,
    StackTrace stackTrace,
    UpdateTenantConfigParameters parameters,
  ) => _mapTenantConfig('updateTenantConfig', exception, stackTrace);
}
