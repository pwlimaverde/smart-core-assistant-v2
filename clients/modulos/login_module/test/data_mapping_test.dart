import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/grpc_error_mapper.dart';
import 'package:login_module/src/features/login/data/jwt_payload.dart';

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
  });
}
