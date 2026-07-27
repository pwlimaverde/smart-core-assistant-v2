import 'package:api_client/api_client.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/data/repositories/login_repository.dart';
import 'package:login_module/src/features/login/data/repositories/logout_repository.dart';
import 'package:login_module/src/features/login/data/repositories/refresh_repository.dart';
import 'package:login_module/src/features/login/domain/errors/auth_errors.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/parameters/login_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/logout_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/refresh_parameters.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Datasource que devolve [dado] ou lança [erro] — a única coisa que o
/// repositório precisa exercitar.
final class _Ds<TData, TParams extends Parameters>
    implements Datasource<TData, TParams> {
  final TData? dado;
  final Object? erro;
  const _Ds({this.dado, this.erro});

  @override
  Future<TData> call(TParams parameters) async {
    if (erro != null) throw erro!;
    return dado!;
  }
}

Session _session() => Session(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  tenantId: 't',
  scopes: const [],
  isSuperuser: false,
);

/// Erros de transporte, um por [GrpcFailureKind] tratado.
final _falhas = <GrpcFailureKind, Object>{
  GrpcFailureKind.unauthenticated: GrpcError.unauthenticated('x'),
  GrpcFailureKind.permissionDenied: GrpcError.permissionDenied('x'),
  GrpcFailureKind.invalidArgument: GrpcError.invalidArgument('x'),
  GrpcFailureKind.failedPrecondition: GrpcError.failedPrecondition('x'),
  GrpcFailureKind.notFound: GrpcError.notFound('x'),
  GrpcFailureKind.alreadyExists: GrpcError.alreadyExists('x'),
  GrpcFailureKind.rateLimited: GrpcError.resourceExhausted('x'),
  GrpcFailureKind.unavailable: GrpcError.unavailable('x'),
  GrpcFailureKind.unknown: GrpcError.internal('x'),
};

void main() {
  const loginParams = LoginParameters(email: 'e@e.com', password: 'p');
  const refreshParams = RefreshParameters(refreshToken: 'rt');
  const logoutParams = LogoutParameters(refreshToken: 'rt');

  group('LoginRepository', () {
    test('sucesso devolve o dado bruto em Success', () async {
      final repo = LoginRepository(
        datasource: _Ds<Session, LoginParameters>(dado: _session()),
      );

      final r = await repo(loginParams);

      expect(r, isA<Success<Session, LoginError>>());
    });

    test(
      'traduz cada natureza de falha no erro previsto da operação',
      () async {
        final esperado = <GrpcFailureKind, Matcher>{
          GrpcFailureKind.unauthenticated: isA<CredenciaisInvalidas>(),
          GrpcFailureKind.notFound: isA<CredenciaisInvalidas>(),
          GrpcFailureKind.permissionDenied: isA<CredenciaisInvalidas>(),
          GrpcFailureKind.invalidArgument: isA<LoginDadosInvalidos>(),
          GrpcFailureKind.failedPrecondition: isA<LoginDadosInvalidos>(),
          GrpcFailureKind.rateLimited: isA<LoginBloqueadoPorTentativas>(),
          GrpcFailureKind.unavailable: isA<LoginIndisponivel>(),
          GrpcFailureKind.alreadyExists: isA<LoginInesperado>(),
          GrpcFailureKind.unknown: isA<LoginInesperado>(),
        };

        for (final entry in esperado.entries) {
          final repo = LoginRepository(
            datasource: _Ds<Session, LoginParameters>(erro: _falhas[entry.key]),
          );
          final r = await repo(loginParams);

          expect(r, isA<Failure<Session, LoginError>>());
          expect(
            (r as Failure<Session, LoginError>).error,
            entry.value,
            reason: '${entry.key} deveria traduzir para ${entry.value}',
          );
        }
      },
    );

    test('exceção fora do transporte vira o caso inesperado', () async {
      final repo = LoginRepository(
        datasource: const _Ds<Session, LoginParameters>(
          erro: FormatException('payload corrompido'),
        ),
      );

      final r = await repo(loginParams);

      expect((r as Failure).error, isA<LoginInesperado>());
    });

    test('a mensagem exibida não carrega o texto da exceção', () async {
      final repo = LoginRepository(
        datasource: const _Ds<Session, LoginParameters>(
          erro: FormatException(r'senha=123456 em C:\segredo.json'),
        ),
      );

      final erro = ((await repo(loginParams)) as Failure).error as LoginError;

      expect(erro.message, isNot(contains('123456')));
      expect(erro.message, isNot(contains('segredo')));
      expect(erro, isA<UnexpectedFailure>());
    });
  });

  group('RefreshRepository', () {
    test('token recusado pelo servidor vira RefreshRejeitado', () async {
      for (final kind in [
        GrpcFailureKind.unauthenticated,
        GrpcFailureKind.permissionDenied,
        GrpcFailureKind.notFound,
        GrpcFailureKind.invalidArgument,
        GrpcFailureKind.failedPrecondition,
      ]) {
        final repo = RefreshRepository(
          datasource: _Ds<Session, RefreshParameters>(erro: _falhas[kind]),
        );

        expect(
          ((await repo(refreshParams)) as Failure).error,
          isA<RefreshRejeitado>(),
          reason: '$kind derruba a sessão',
        );
      }
    });

    test('servidor inalcançável NÃO é rejeição — é indisponibilidade', () async {
      // A distinção existe para não deslogar o usuário por instabilidade de rede.
      for (final kind in [
        GrpcFailureKind.unavailable,
        GrpcFailureKind.rateLimited,
      ]) {
        final repo = RefreshRepository(
          datasource: _Ds<Session, RefreshParameters>(erro: _falhas[kind]),
        );

        final erro = ((await repo(refreshParams)) as Failure).error;
        expect(erro, isA<RefreshIndisponivel>());
        expect(erro, isA<NetworkFailure>());
        expect(erro, isNot(isA<UnauthorizedFailure>()));
      }
    });

    test('inesperado quando a falha não vem do transporte', () async {
      final repo = RefreshRepository(
        datasource: const _Ds<Session, RefreshParameters>(erro: 'oops'),
      );

      expect(
        ((await repo(refreshParams)) as Failure).error,
        isA<RefreshInesperado>(),
      );
    });
  });

  group('LogoutRepository', () {
    test('sucesso devolve Unit', () async {
      final repo = LogoutRepository(
        datasource: const _Ds<Unit, LogoutParameters>(dado: unit),
      );

      expect(await repo(logoutParams), isA<Success<Unit, LogoutError>>());
    });

    test(
      'recusa do servidor é informativa (a sessão local já foi encerrada)',
      () async {
        final repo = LogoutRepository(
          datasource: _Ds<Unit, LogoutParameters>(
            erro: _falhas[GrpcFailureKind.unauthenticated],
          ),
        );

        expect(
          ((await repo(logoutParams)) as Failure).error,
          isA<LogoutRejeitado>(),
        );
      },
    );

    test('servidor inalcançável avisa que o token não foi revogado', () async {
      final repo = LogoutRepository(
        datasource: _Ds<Unit, LogoutParameters>(
          erro: _falhas[GrpcFailureKind.unavailable],
        ),
      );

      final erro = ((await repo(logoutParams)) as Failure).error as LogoutError;
      expect(erro, isA<LogoutIndisponivel>());
      expect(erro.message, contains('revogá-la'));
    });

    test('inesperado quando a falha não vem do transporte', () async {
      final repo = LogoutRepository(
        datasource: _Ds<Unit, LogoutParameters>(erro: StateError('bug')),
      );

      expect(
        ((await repo(logoutParams)) as Failure).error,
        isA<LogoutInesperado>(),
      );
    });
  });
}
