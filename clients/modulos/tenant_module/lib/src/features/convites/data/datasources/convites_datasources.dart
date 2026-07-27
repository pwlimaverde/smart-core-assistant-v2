import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/accepted_tenant_user.dart';
import '../../domain/model/tenant_invite.dart';
import '../../domain/parameters/convites_parameters.dart';

/// Datasources da feature de convites: I/O gRPC e conversão protobuf → domínio.
///
/// Todos burros (sem `try/catch`): a exceção sobe crua para o `mapError`.

/// Cria o convite e devolve o registro com o token gerado.
final class CreateInviteDatasource
    implements Datasource<TenantInviteCreated, CreateInviteParameters> {
  final proto.AdminServiceClient _client;

  const CreateInviteDatasource({required this._client});

  @override
  Future<TenantInviteCreated> call(CreateInviteParameters parameters) async {
    final resp = await _client.createInvite(
      proto.CreateInviteRequest(
        email: parameters.email,
        name: parameters.name,
        role: parameters.role,
        modulePermissions: parameters.modulePermissions,
        flowPermissions: parameters.flowPermissions,
      ),
    );
    final i = resp.invite;
    return TenantInviteCreated(
      id: i.id,
      tenantId: i.tenantId,
      email: i.email,
      name: i.name,
      role: i.role,
      token: i.token,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(i.expiresAt.toInt()),
      used: i.used,
      createdAt: DateTime.fromMillisecondsSinceEpoch(i.createdAt.toInt()),
    );
  }
}

/// Lista os convites do tenant da sessão.
final class ListInvitesDatasource
    implements Datasource<List<TenantInvite>, NoParams> {
  final proto.AdminServiceClient _client;

  const ListInvitesDatasource({required this._client});

  @override
  Future<List<TenantInvite>> call(NoParams parameters) async {
    final resp = await _client.listInvites(proto.ListInvitesRequest());
    return resp.invites
        .map(
          (i) => TenantInvite(
            id: i.id,
            email: i.email,
            name: i.name,
            role: i.role,
            modulePermissions: i.modulePermissions,
            flowPermissions: i.flowPermissions,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(i.expiresAt.toInt()),
            used: i.used,
            revoked: i.revoked,
            createdAt: DateTime.fromMillisecondsSinceEpoch(i.createdAt.toInt()),
          ),
        )
        .toList(growable: false);
  }
}

/// Revoga um convite pendente.
final class RevokeInviteDatasource
    implements Datasource<Unit, RevokeInviteParameters> {
  final proto.AdminServiceClient _client;

  const RevokeInviteDatasource({required this._client});

  @override
  Future<Unit> call(RevokeInviteParameters parameters) async {
    await _client.revokeInvite(
      proto.RevokeInviteRequest(inviteId: parameters.inviteId),
    );
    return unit;
  }
}

/// Aceita o convite e cria a conta do convidado (rota pública).
final class AcceptInviteDatasource
    implements Datasource<AcceptedTenantUser, AcceptInviteParameters> {
  final proto.AdminServiceClient _client;

  const AcceptInviteDatasource({required this._client});

  @override
  Future<AcceptedTenantUser> call(AcceptInviteParameters parameters) async {
    final resp = await _client.acceptInvite(
      proto.AcceptInviteRequest(
        token: parameters.token,
        username: parameters.username,
        email: parameters.email,
        password: parameters.password,
      ),
    );
    final u = resp.tenantUser;
    return AcceptedTenantUser(
      id: u.id,
      userId: u.userId,
      tenantId: u.tenantId,
      role: u.role,
      modulePermissions: u.modulePermissions,
      flowPermissions: u.flowPermissions,
      isActive: u.isActive,
    );
  }
}
