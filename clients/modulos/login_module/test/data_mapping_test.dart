import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/grpc_error_mapper.dart';
import 'package:login_module/src/features/login/data/jwt_payload.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/parameters/login_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/logout_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/refresh_parameters.dart';

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

/// Monta um JWT fake (header.payload.assinatura) — só o payload importa aqui.
String _fakeJwt(Map<String, dynamic> payload) =>
    '${_b64({'alg': 'HS256'})}.${_b64(payload)}.assinatura';

void main() {
  group('mapGrpcError', () {
    const fallback = ErrorAuth();
    test('unauthenticated → ErrorUnauthorized', () {
      expect(
        mapGrpcError(GrpcError.unauthenticated('x'), fallback),
        isA<ErrorUnauthorized>(),
      );
    });
    test('invalidArgument → ErrorValidation', () {
      expect(
        mapGrpcError(GrpcError.invalidArgument('x'), fallback),
        isA<ErrorValidation>(),
      );
    });
    test('unavailable → ErrorNetwork', () {
      expect(
        mapGrpcError(GrpcError.unavailable('x'), fallback),
        isA<ErrorNetwork>(),
      );
    });
    test('código não mapeado → fallback', () {
      expect(mapGrpcError(GrpcError.internal('x'), fallback), fallback);
    });
  });

  group('mapGrpcError — casos adicionais', () {
    const fallback = ErrorAuth();
    test('permissionDenied → ErrorUnauthorized com mensagem', () {
      final err = mapGrpcError(GrpcError.permissionDenied('x'), fallback);
      expect(err, isA<ErrorUnauthorized>());
      expect((err as ErrorUnauthorized).message, 'Acesso negado.');
    });
    test('resourceExhausted → ErrorAuth com mensagem de rate limit', () {
      final err = mapGrpcError(GrpcError.resourceExhausted('x'), fallback);
      expect(err, isA<ErrorAuth>());
    });
    test('deadlineExceeded → ErrorNetwork', () {
      expect(
        mapGrpcError(GrpcError.deadlineExceeded('x'), fallback),
        isA<ErrorNetwork>(),
      );
    });
  });

  group('JwtPayload.decode', () {
    test('extrai exp/tenant/scopes/isSuperuser do payload', () {
      final exp =
          DateTime.now().add(const Duration(minutes: 15)).millisecondsSinceEpoch ~/
              1000;
      final token = _fakeJwt({
        'exp': exp,
        'tenant_id': 'tenant-9',
        'scopes': ['a', 'b'],
        'is_superuser': true,
      });

      final s = JwtPayload.decode(token).paraSession(
        accessToken: token,
        refreshToken: 'r',
      );

      expect(s.tenantId, 'tenant-9');
      expect(s.scopes, ['a', 'b']);
      expect(s.isSuperuser, isTrue);
      expect(s.isExpired, isFalse);
    });

    test('token malformado → payload conservador (expirado)', () {
      final s = JwtPayload.decode('lixo').paraSession(
        accessToken: 'lixo',
        refreshToken: 'r',
      );
      expect(s.isExpired, isTrue);
      expect(s.scopes, isEmpty);
    });

    test('token com apenas um segmento → payload conservador', () {
      final s = JwtPayload.decode('sempontos')
          .paraSession(accessToken: 'sempontos', refreshToken: 'r');
      expect(s.isExpired, isTrue);
      expect(s.tenantId, '');
    });

    test('paraSession popula accessToken e refreshToken', () {
      final exp =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
              1000;
      final token = _fakeJwt({'exp': exp, 'tenant_id': 't1'});
      final s = JwtPayload.decode(token)
          .paraSession(accessToken: token, refreshToken: 'rtoken');
      expect(s.accessToken, token);
      expect(s.refreshToken, 'rtoken');
    });
  });

  group('Session', () {
    test('isExpired é false quando expiresAt é no futuro', () {
      final s = Session(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        tenantId: 't',
        scopes: const [],
        isSuperuser: false,
      );
      expect(s.isExpired, isFalse);
    });

    test('isExpired é true quando expiresAt está no passado', () {
      final s = Session(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
        tenantId: 't',
        scopes: const [],
        isSuperuser: false,
      );
      expect(s.isExpired, isTrue);
    });
  });

  group('Parâmetros — propriedade error', () {
    test('LoginParameters.error é ErrorAuth', () {
      const p = LoginParameters(email: 'e@e.com', password: 'p');
      expect(p.error, isA<ErrorAuth>());
    });

    test('LogoutParameters.error é ErrorAuth', () {
      const p = LogoutParameters();
      expect(p.error, isA<ErrorAuth>());
    });

    test('RefreshParameters.error é ErrorUnauthorized', () {
      const p = RefreshParameters(refreshToken: 'rt');
      expect(p.error, isA<ErrorUnauthorized>());
    });
  });
}
