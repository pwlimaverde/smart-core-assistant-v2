import 'package:meta/meta.dart';

/// Vínculo usuário↔tenant↔papel↔permissões (gestão de usuários, N3.2).
///
/// [modulePermissions] é a lista PLANA de escopos do usuário (ex.:
/// `"tenant:admin"`, `"atendimentos:write"`) — não uma estrutura aninhada por
/// módulo com view/edit/delete. [flowPermissions] são os IDs de
/// `FluxoAtendimento` que o usuário pode ver no Kanban.
@immutable
class TenantUser {
  final int id;
  final int userId;
  final String role;
  final List<String> modulePermissions;
  final List<int> flowPermissions;
  final bool isActive;
  final DateTime createdAt;

  const TenantUser({
    required this.id,
    required this.userId,
    required this.role,
    required this.modulePermissions,
    required this.flowPermissions,
    required this.isActive,
    required this.createdAt,
  });
}

/// Vínculo criado ao aceitar um convite (`AcceptInvite`).
@immutable
class AcceptedTenantUser {
  final int id;
  final int userId;
  final String tenantId;
  final String role;
  final List<String> modulePermissions;
  final List<int> flowPermissions;
  final bool isActive;

  const AcceptedTenantUser({
    required this.id,
    required this.userId,
    required this.tenantId,
    required this.role,
    required this.modulePermissions,
    required this.flowPermissions,
    required this.isActive,
  });
}
