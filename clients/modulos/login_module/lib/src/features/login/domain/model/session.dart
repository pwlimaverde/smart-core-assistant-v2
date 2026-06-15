import 'package:meta/meta.dart';

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
}
