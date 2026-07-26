import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/usuarios_errors.dart';
import '../model/tenant_user.dart';
import '../parameters/usuarios_parameters.dart';

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'tenant_module.usuarios',
      error: exception,
      stackTrace: stackTrace,
    );

final class ListTenantUsersUsecase
    extends
        UsecaseBaseCallData<
          List<TenantUser>,
          List<TenantUser>,
          NoParams,
          TenantUsuariosError
        > {
  const ListTenantUsersUsecase({required super.repository});

  @override
  ProcessData<List<TenantUser>, List<TenantUser>, NoParams, TenantUsuariosError>
  get process => _process;

  @override
  TenantUsuariosError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listTenantUsers', exception, stackTrace);
    return const UsuariosInesperado();
  }

  /// Regra da feature: ativos primeiro, depois os inativos — a tela existe para
  /// administrar quem está em operação.
  static ReturnSuccessOrError<List<TenantUser>, TenantUsuariosError> _process(
    List<TenantUser> data,
    NoParams parameters,
  ) {
    final ordenados = [...data]
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return a.createdAt.compareTo(b.createdAt);
      });
    return Success(List.unmodifiable(ordenados));
  }
}

final class UpdateTenantUserUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          UpdateTenantUserParameters,
          TenantUsuariosError
        > {
  const UpdateTenantUserUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, UpdateTenantUserParameters, TenantUsuariosError>
  get process => _process;

  @override
  TenantUsuariosError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('updateTenantUser', exception, stackTrace);
    return const UsuariosInesperado();
  }

  static ReturnSuccessOrError<Unit, TenantUsuariosError> _process(
    Unit data,
    UpdateTenantUserParameters parameters,
  ) => const Success(unit);
}
