import 'package:meta/meta.dart';

/// Vínculo criado ao aceitar um convite (`AcceptInvite`).
@immutable
final class AcceptedTenantUser {
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
