import 'package:meta/meta.dart';

/// Predicado puro de RBAC de UI: escopos que concedem administração do tenant
/// (telas de convites/usuarios/config). Centraliza a regra usada tanto no guard
/// de rota quanto no menu — um unico ponto evita que os dois divirjam.
bool scopesGrantTenantAdmin(List<String> scopes) =>
    scopes.contains('tenant:admin') || scopes.contains('*');

/// Sessão autenticada do usuário.
///
/// Imutável/sendable: pode ser reexecutada com segurança entre camadas. O
/// [accessToken] vive apenas em memória; o [refreshToken] é o único persistido
/// (secure storage) — ver `TokenLocalDatasource`.
@immutable
final class Session {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String tenantId;
  final List<String> scopes;
  final bool isSuperuser;

  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.tenantId,
    required this.scopes,
    required this.isSuperuser,
  });

  /// `true` quando o access token já passou da expiração.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// `true` quando a sessão pode administrar o tenant (RBAC de UI).
  bool get isTenantAdmin => scopesGrantTenantAdmin(scopes);
}
