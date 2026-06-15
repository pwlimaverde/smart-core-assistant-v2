import 'dart:convert';

import '../domain/model/session.dart';

/// Decodifica o payload do access token (JWT) **sem verificar assinatura** —
/// a verificação é responsabilidade exclusiva do servidor. No client serve
/// apenas para popular a [Session] (expiração, tenant, escopos, superusuário)
/// e melhorar a UX. Nunca confie nessas claims para decisão de segurança.
final class JwtPayload {
  final DateTime expiresAt;
  final String tenantId;
  final List<String> scopes;
  final bool isSuperuser;

  const JwtPayload({
    required this.expiresAt,
    required this.tenantId,
    required this.scopes,
    required this.isSuperuser,
  });

  /// Decodifica o segmento de payload (`header.payload.signature`). Em qualquer
  /// falha, devolve um payload conservador (expira já, sem escopos).
  factory JwtPayload.decode(String accessToken) {
    try {
      final partes = accessToken.split('.');
      if (partes.length < 2) return JwtPayload._vazio();
      final normalizado = base64Url.normalize(partes[1]);
      final json = jsonDecode(utf8.decode(base64Url.decode(normalizado)))
          as Map<String, dynamic>;

      final exp = json['exp'];
      final expiresAt = exp is int
          ? DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true)
          : DateTime.now();

      final scopesRaw = json['scopes'];
      final scopes = scopesRaw is List
          ? scopesRaw.map((e) => '$e').toList(growable: false)
          : const <String>[];

      return JwtPayload(
        expiresAt: expiresAt,
        tenantId: (json['tenant_id'] as String?) ?? '',
        scopes: scopes,
        isSuperuser: (json['is_superuser'] as bool?) ?? false,
      );
    } catch (_) {
      return JwtPayload._vazio();
    }
  }

  factory JwtPayload._vazio() => JwtPayload(
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        tenantId: '',
        scopes: const [],
        isSuperuser: false,
      );

  /// Monta a [Session] combinando as claims decodificadas com os tokens crus.
  Session paraSession({
    required String accessToken,
    required String refreshToken,
  }) =>
      Session(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresAt: expiresAt,
        tenantId: tenantId,
        scopes: scopes,
        isSuperuser: isSuperuser,
      );
}
