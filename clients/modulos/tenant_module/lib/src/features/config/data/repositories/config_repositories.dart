import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/config_errors.dart';
import '../../domain/model/tenant_config.dart';
import '../../domain/parameters/config_parameters.dart';

TenantConfigError _mapConfig(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  // `parameters` carrega as chaves de API do tenant: nunca vai para o log.
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.config',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const ConfigAcessoNegado(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.notFound => const ConfigDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const ConfigIndisponivel(),
    GrpcFailureKind.unknown => const ConfigInesperado(),
  };
}

final class GetMyTenantConfigRepository
    extends RepositoryBase<TenantConfig, NoParams, TenantConfigError> {
  const GetMyTenantConfigRepository({required super.datasource});

  @override
  TenantConfigError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapConfig('getMyTenantConfig', exception, stackTrace);
}

final class UpdateMyTenantConfigRepository
    extends
        RepositoryBase<
          Unit,
          UpdateMyTenantConfigParameters,
          TenantConfigError
        > {
  const UpdateMyTenantConfigRepository({required super.datasource});

  @override
  TenantConfigError mapError(
    Object exception,
    StackTrace stackTrace,
    UpdateMyTenantConfigParameters parameters,
  ) => _mapConfig('updateMyTenantConfig', exception, stackTrace);
}
