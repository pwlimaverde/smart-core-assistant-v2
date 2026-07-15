import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../domain/model/tenant_user.dart';
import '../../../domain/usecases/list_tenant_users_usecase.dart';
import '../../../domain/usecases/update_tenant_user_usecase.dart';

final class TenantUsersController extends BaseController<List<TenantUser>> {
  final ListTenantUsersUsecase _listUsecase;
  final UpdateTenantUserUsecase _updateUsecase;

  TenantUsersController({
    required this._listUsecase,
    required this._updateUsecase,
  });

  Future<void> fetchUsers() => execute(() => _listUsecase.call());

  Future<ReturnSuccessOrError<Unit>> updateUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) async {
    final res = await _updateUsecase.call(
      userId: userId,
      role: role,
      modulePermissions: modulePermissions,
      flowPermissions: flowPermissions,
    );
    if (res is SuccessReturn<Unit>) {
      await fetchUsers();
    }
    return res;
  }
}
