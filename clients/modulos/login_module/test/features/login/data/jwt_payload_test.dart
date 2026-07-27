import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/jwt_payload.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// JWT de mentira (`header.payload.assinatura`) — só o payload importa: a
/// verificação de assinatura é exclusividade do servidor.
String _fakeJwt(Map<String, dynamic> payload) =>
    '${_b64({'alg': 'HS256'})}.${_b64(payload)}.assinatura';

int _epoch(Duration daAgora) =>
    DateTime.now().add(daAgora).millisecondsSinceEpoch ~/
    Duration.millisecondsPerSecond;

void main() {
  group('JwtPayload.decode', () {
    test('extrai exp/tenant/scopes/isSuperuser do payload', () {
      final token = _fakeJwt({
        'exp': _epoch(const Duration(minutes: 15)),
        'tenant_id': 'tenant-9',
        'scopes': ['a', 'b'],
        'is_superuser': true,
      });

      final s = JwtPayload.decode(
        token,
      ).paraSession(accessToken: token, refreshToken: 'r');

      expect(s.tenantId, 'tenant-9');
      expect(s.scopes, ['a', 'b']);
      expect(s.isSuperuser, isTrue);
      expect(s.isExpired, isFalse);
    });

    test('token malformado → payload conservador (expirado, sem escopo)', () {
      final s = JwtPayload.decode(
        'lixo',
      ).paraSession(accessToken: 'lixo', refreshToken: 'r');

      expect(s.isExpired, isTrue);
      expect(s.scopes, isEmpty);
    });

    test('token com um único segmento → payload conservador', () {
      final s = JwtPayload.decode(
        'sempontos',
      ).paraSession(accessToken: 'sempontos', refreshToken: 'r');

      expect(s.isExpired, isTrue);
      expect(s.tenantId, '');
    });

    test('segmento de payload ilegível cai no catch e degrada com segurança', () {
      // Dois segmentos (passa da checagem de formato) mas o meio não é base64
      // válido: é o caminho em que o decode precisa não lançar.
      final s = JwtPayload.decode(
        'cabecalho.!!!nao-e-base64!!!.assinatura',
      ).paraSession(accessToken: 'x', refreshToken: 'r');

      expect(s.isExpired, isTrue);
      expect(s.tenantId, '');
      expect(s.scopes, isEmpty);
      expect(s.isSuperuser, isFalse);
    });

    test('payload sem exp não é tratado como expirado imediato', () {
      // Sem `exp`, o decode assume "agora" — a sessão nasce no limite, e a
      // próxima checagem a considera expirada. O que importa é não estourar.
      final token = _fakeJwt({'tenant_id': 't1'});

      final p = JwtPayload.decode(token);

      expect(p.tenantId, 't1');
      expect(p.scopes, isEmpty);
      expect(p.isSuperuser, isFalse);
    });

    test('scopes com tipo inesperado degrada para lista vazia', () {
      final token = _fakeJwt({
        'exp': _epoch(const Duration(minutes: 5)),
        'scopes': 'nao-e-lista',
      });

      expect(JwtPayload.decode(token).scopes, isEmpty);
    });

    test('scopes numéricos são convertidos para texto', () {
      final token = _fakeJwt({
        'exp': _epoch(const Duration(minutes: 5)),
        'scopes': [1, 2],
      });

      expect(JwtPayload.decode(token).scopes, ['1', '2']);
    });

    test('paraSession preserva os dois tokens crus', () {
      final token = _fakeJwt({
        'exp': _epoch(const Duration(hours: 1)),
        'tenant_id': 't1',
      });

      final s = JwtPayload.decode(
        token,
      ).paraSession(accessToken: token, refreshToken: 'rtoken');

      expect(s.accessToken, token);
      expect(s.refreshToken, 'rtoken');
    });
  });

  group('Session', () {
    Session comEscopos(
      List<String> scopes, {
      Duration ttl = const Duration(minutes: 15),
    }) => Session(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(ttl),
      tenantId: 't',
      scopes: scopes,
      isSuperuser: false,
    );

    test('isExpired reflete a expiração do access token', () {
      expect(comEscopos(const []).isExpired, isFalse);
      expect(
        comEscopos(const [], ttl: const Duration(seconds: -1)).isExpired,
        isTrue,
      );
    });

    test('isTenantAdmin exige tenant:admin ou o curinga', () {
      expect(comEscopos(const ['tenant:admin']).isTenantAdmin, isTrue);
      expect(comEscopos(const ['*']).isTenantAdmin, isTrue);
      expect(comEscopos(const ['atendimentos:read']).isTenantAdmin, isFalse);
      expect(comEscopos(const []).isTenantAdmin, isFalse);
    });

    test('scopesGrantTenantAdmin é o mesmo predicado do guard e do menu', () {
      // Um único ponto de verdade evita que rota e menu divirjam.
      expect(scopesGrantTenantAdmin(const ['tenant:admin']), isTrue);
      expect(scopesGrantTenantAdmin(const ['outro']), isFalse);
    });
  });
}
