import 'package:meta/meta.dart';

/// Convite recém-criado. É o ÚNICO ponto onde o [token] aparece (momento da
/// criação); as listagens (`TenantInvite`) nunca o expõem.
@immutable
class TenantInviteCreated {
  final String id;
  final String tenantId;
  final String email;
  final String name;
  final String role;
  final String token;
  final DateTime expiresAt;
  final bool used;
  final DateTime createdAt;

  const TenantInviteCreated({
    required this.id,
    required this.tenantId,
    required this.email,
    required this.name,
    required this.role,
    required this.token,
    required this.expiresAt,
    required this.used,
    required this.createdAt,
  });
}

/// Item de listagem de convite (sem `token`).
@immutable
class TenantInvite {
  final String id;
  final String email;
  final String name;
  final String role;
  final List<String> modulePermissions;
  final List<int> flowPermissions;
  final DateTime expiresAt;
  final bool used;
  final bool revoked;
  final DateTime createdAt;

  const TenantInvite({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.modulePermissions,
    required this.flowPermissions,
    required this.expiresAt,
    required this.used,
    required this.revoked,
    required this.createdAt,
  });

  /// `true` quando o convite ainda pode ser aceito (não usado, não revogado,
  /// não expirado).
  bool get pendente => !used && !revoked && expiresAt.isAfter(DateTime.now());
}
