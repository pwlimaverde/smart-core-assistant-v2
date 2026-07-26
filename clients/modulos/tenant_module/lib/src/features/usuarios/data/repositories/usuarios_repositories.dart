import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/usuarios_errors.dart';
import '../../domain/model/tenant_user.dart';
import '../../domain/parameters/usuarios_parameters.dart';

TenantUsuariosError _mapUsuarios(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.usuarios',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const UsuariosAcessoNegado(),
    GrpcFailureKind.notFound => const UsuarioNaoEncontrado(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition ||
    GrpcFailureKind.alreadyExists => const UsuariosDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const UsuariosIndisponivel(),
    GrpcFailureKind.unknown => const UsuariosInesperado(),
  };
}

final class ListTenantUsersRepository
    extends RepositoryBase<List<TenantUser>, NoParams, TenantUsuariosError> {
  const ListTenantUsersRepository({required super.datasource});

  @override
  TenantUsuariosError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapUsuarios('listTenantUsers', exception, stackTrace);
}

final class UpdateTenantUserRepository
    extends
        RepositoryBase<Unit, UpdateTenantUserParameters, TenantUsuariosError> {
  const UpdateTenantUserRepository({required super.datasource});

  @override
  TenantUsuariosError mapError(
    Object exception,
    StackTrace stackTrace,
    UpdateTenantUserParameters parameters,
  ) => _mapUsuarios('updateTenantUser', exception, stackTrace);
}
