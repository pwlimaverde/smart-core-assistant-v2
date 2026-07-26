import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/usuarios_errors.dart';
import '../../domain/model/tenant_user.dart';
import '../../domain/parameters/usuarios_parameters.dart';
import '../../domain/usecases/usuarios_usecases.dart';

final class TenantUsersController extends BaseController<List<TenantUser>> {
  final ListTenantUsersUsecase _listUsecase;
  final UpdateTenantUserUsecase _updateUsecase;

  TenantUsersController({
    required this._listUsecase,
    required this._updateUsecase,
  });

  Future<void> fetchUsers() => execute(() => _listUsecase(noParams));

  Future<ReturnSuccessOrError<Unit, TenantUsuariosError>> updateUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) async {
    final res = await _updateUsecase(
      UpdateTenantUserParameters(
        userId: userId,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      ),
    );
    if (res is Success) await fetchUsers();
    return res;
  }
}
