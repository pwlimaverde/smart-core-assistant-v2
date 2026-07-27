import 'dart:convert';

import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/datasources/login_grpc_datasource.dart';
import 'package:login_module/src/features/login/data/datasources/logout_grpc_datasource.dart';
import 'package:login_module/src/features/login/data/datasources/refresh_grpc_datasource.dart';
import 'package:login_module/src/features/login/domain/parameters/login_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/logout_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/refresh_parameters.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

class _MockAuthClient extends Mock implements AuthServiceClient {}

String _b64(Map<String, dynamic> m) =>
    base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

String _jwt({
  required Duration ttl,
  String tenant = 'tenant-1',
  List<String> scopes = const ['atendimentos:read'],
  bool superuser = false,
}) {
  final exp =
      DateTime.now().add(ttl).millisecondsSinceEpoch ~/
      Duration.millisecondsPerSecond;
  return '${_b64({'alg': 'HS256'})}.'
      '${_b64({'exp': exp, 'tenant_id': tenant, 'scopes': scopes, 'is_superuser': superuser})}.assinatura';
}

void main() {
  late _MockAuthClient client;

  setUpAll(() {
    registerFallbackValue(LoginRequest());
    registerFallbackValue(RefreshRequest());
    registerFallbackValue(LogoutRequest());
  });

  setUp(() => client = _MockAuthClient());

  group('LoginGrpcDatasource', () {
    test(
      'envia e-mail/senha e monta a Session a partir do access token',
      () async {
        final access = _jwt(
          ttl: const Duration(minutes: 15),
          tenant: 'tenant-9',
          scopes: const ['a', 'b'],
          superuser: true,
        );
        when(() => client.login(any())).thenAnswer(
          (_) => respostaGrpc(
            AuthResponse(accessToken: access, refreshToken: 'refresh-1'),
          ),
        );

        final session = await LoginGrpcDatasource(client: client)(
          const LoginParameters(email: 'e@e.com', password: 'senha'),
        );

        final enviado = verify(
          () => client.login(captureAny()),
        ).captured.single;
        expect((enviado as LoginRequest).email, 'e@e.com');
        expect(enviado.password, 'senha');
        expect(session.accessToken, access);
        expect(session.refreshToken, 'refresh-1');
        expect(session.tenantId, 'tenant-9');
        expect(session.scopes, ['a', 'b']);
        expect(session.isSuperuser, isTrue);
        expect(session.isExpired, isFalse);
      },
    );

    test(
      'deixa a falha do transporte subir crua (o repositório traduz)',
      () async {
        when(() => client.login(any())).thenAnswer(
          (_) => falhaGrpc(GrpcError.unauthenticated('errors.auth')),
        );

        await expectLater(
          LoginGrpcDatasource(client: client)(
            const LoginParameters(email: 'e@e.com', password: 'errada'),
          ),
          throwsA(isA<GrpcError>()),
        );
      },
    );

    test('token de resposta malformado sobe como falha de dados', () async {
      // JwtPayload.decode não lança: devolve payload conservador (expirado).
      // O contrato do datasource é não mascarar isso — quem decide é o domínio.
      when(() => client.login(any())).thenAnswer(
        (_) => respostaGrpc(
          AuthResponse(accessToken: 'nao-e-um-jwt', refreshToken: 'r'),
        ),
      );

      final session = await LoginGrpcDatasource(client: client)(
        const LoginParameters(email: 'e@e.com', password: 'senha'),
      );

      expect(session.isExpired, isTrue);
      expect(session.scopes, isEmpty);
      expect(session.tenantId, isEmpty);
    });
  });

  group('RefreshGrpcDatasource', () {
    test('envia o refresh persistido e devolve o par rotacionado', () async {
      final access = _jwt(ttl: const Duration(minutes: 15));
      when(() => client.refresh(any())).thenAnswer(
        (_) => respostaGrpc(
          AuthResponse(accessToken: access, refreshToken: 'refresh-2'),
        ),
      );

      final session = await RefreshGrpcDatasource(client: client)(
        const RefreshParameters(refreshToken: 'refresh-1'),
      );

      final enviado =
          verify(() => client.refresh(captureAny())).captured.single
              as RefreshRequest;
      expect(enviado.refreshToken, 'refresh-1');
      expect(session.refreshToken, 'refresh-2', reason: 'rotacionou');
    });

    test('deixa a falha do transporte subir crua', () async {
      when(
        () => client.refresh(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('reuse')));

      await expectLater(
        RefreshGrpcDatasource(client: client)(
          const RefreshParameters(refreshToken: 'usado'),
        ),
        throwsA(isA<GrpcError>()),
      );
    });
  });

  group('LogoutGrpcDatasource', () {
    test('envia o refresh token quando existe', () async {
      when(
        () => client.logout(any()),
      ).thenAnswer((_) => respostaGrpc(LogoutResponse()));

      final r = await LogoutGrpcDatasource(client: client)(
        const LogoutParameters(refreshToken: 'refresh-1'),
      );

      final enviado =
          verify(() => client.logout(captureAny())).captured.single
              as LogoutRequest;
      expect(enviado.refreshToken, 'refresh-1');
      expect(r, unit);
    });

    test(
      'sem refresh persistido, envia string vazia (revoga só o access)',
      () async {
        when(
          () => client.logout(any()),
        ).thenAnswer((_) => respostaGrpc(LogoutResponse()));

        await LogoutGrpcDatasource(client: client)(const LogoutParameters());

        final enviado =
            verify(() => client.logout(captureAny())).captured.single
                as LogoutRequest;
        expect(enviado.refreshToken, isEmpty);
      },
    );

    test('deixa a falha do transporte subir crua', () async {
      when(
        () => client.logout(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));

      await expectLater(
        LogoutGrpcDatasource(client: client)(const LogoutParameters()),
        throwsA(isA<GrpcError>()),
      );
    });
  });
}
