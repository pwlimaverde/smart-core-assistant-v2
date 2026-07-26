import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant_user.dart';
import '../../domain/parameters/usuarios_parameters.dart';

/// Lista os usuários do tenant da sessão.
final class ListTenantUsersDatasource
    implements Datasource<List<TenantUser>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListTenantUsersDatasource({required this._client});

  @override
  Future<List<TenantUser>> call(NoParams parameters) async {
    final resp = await _client.listTenantUsers(proto.ListTenantUsersRequest());
    return resp.users
        .map(
          (u) => TenantUser(
            id: u.id,
            userId: u.userId,
            role: u.role,
            modulePermissions: u.modulePermissions,
            flowPermissions: u.flowPermissions,
            isActive: u.isActive,
            createdAt: DateTime.fromMillisecondsSinceEpoch(u.createdAt.toInt()),
          ),
        )
        .toList(growable: false);
  }
}

/// Atualiza papel e permissões de um usuário.
///
/// As flags `set_*` do contrato são o que distingue "não mexer" de "limpar": um
/// campo `null` nos parâmetros vira `set_x: false`, e o servidor preserva o valor
/// atual.
final class UpdateTenantUserDatasource
    implements Datasource<Unit, UpdateTenantUserParameters> {
  final proto.AdminServiceClient _client;

  const UpdateTenantUserDatasource({required this._client});

  @override
  Future<Unit> call(UpdateTenantUserParameters parameters) async {
    await _client.updateTenantUser(
      proto.UpdateTenantUserRequest(
        userId: parameters.userId,
        setRole: parameters.role != null,
        role: parameters.role ?? '',
        setModulePermissions: parameters.modulePermissions != null,
        modulePermissions: parameters.modulePermissions ?? const [],
        setFlowPermissions: parameters.flowPermissions != null,
        flowPermissions: parameters.flowPermissions ?? const [],
      ),
    );
    return unit;
  }
}
