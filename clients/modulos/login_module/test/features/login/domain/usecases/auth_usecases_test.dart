import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/domain/errors/auth_errors.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/parameters/login_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/logout_parameters.dart';
import 'package:login_module/src/features/login/domain/parameters/refresh_parameters.dart';
import 'package:login_module/src/features/login/domain/usecases/login_usecase.dart';
import 'package:login_module/src/features/login/domain/usecases/logout_usecase.dart';
import 'package:login_module/src/features/login/domain/usecases/refresh_token_usecase.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Repositório falso: já devolve `Success`/`Failure` (é o contrato da fronteira).
final class _Repo<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  final ReturnSuccessOrError<TData, TError> resultado;
  int chamadas = 0;
  _Repo(this.resultado);

  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    chamadas++;
    return resultado;
  }
}

/// Repositório que **quebra o contrato**: lança em vez de devolver `Failure`.
/// A base protege o chamador disso, convertendo via `onUnexpected`.
final class _RepoQueLanca<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    throw StateError('repositorio fora do contrato');
  }
}

Session _session() => Session(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  tenantId: 't',
  scopes: const ['x'],
  isSuperuser: false,
);

void main() {
  const loginParams = LoginParameters(email: 'e@e.com', password: 'p');
  const refreshParams = RefreshParameters(refreshToken: 'rt');
  const logoutParams = LogoutParameters();

  group('LoginUsecase', () {
    test('sucesso repassa a Session (process passthrough)', () async {
      final repo = _Repo<Session, LoginParameters, LoginError>(
        Success(_session()),
      );

      final r = await LoginUsecase(repository: repo)(loginParams);

      expect(r, isA<Success<Session, LoginError>>());
      expect((r as Success).value.accessToken, 'a');
      expect(repo.chamadas, 1);
    });

    test(
      'erro do repositório faz curto-circuito preservando o caso concreto',
      () async {
        final repo = _Repo<Session, LoginParameters, LoginError>(
          const Failure(CredenciaisInvalidas()),
        );

        final r = await LoginUsecase(repository: repo)(loginParams);

        expect((r as Failure).error, isA<CredenciaisInvalidas>());
      },
    );

    test(
      'repositório fora do contrato cai em onUnexpected, sem propagar',
      () async {
        final usecase = LoginUsecase(
          repository: _RepoQueLanca<Session, LoginParameters, LoginError>(),
        );

        final r = await usecase(loginParams);

        expect((r as Failure).error, isA<LoginInesperado>());
      },
    );
  });

  group('RefreshTokenUsecase', () {
    test('sucesso repassa a Session rotacionada', () async {
      final repo = _Repo<Session, RefreshParameters, RefreshError>(
        Success(_session()),
      );

      final r = await RefreshTokenUsecase(repository: repo)(refreshParams);

      expect((r as Success).value.refreshToken, 'r');
    });

    test('erro do repositório sobe como erro do usecase', () async {
      final repo = _Repo<Session, RefreshParameters, RefreshError>(
        const Failure(RefreshRejeitado()),
      );

      final r = await RefreshTokenUsecase(repository: repo)(refreshParams);

      expect((r as Failure).error, isA<RefreshRejeitado>());
    });

    test('repositório fora do contrato cai em onUnexpected', () async {
      final usecase = RefreshTokenUsecase(
        repository: _RepoQueLanca<Session, RefreshParameters, RefreshError>(),
      );

      expect(
        ((await usecase(refreshParams)) as Failure).error,
        isA<RefreshInesperado>(),
      );
    });
  });

  group('LogoutUsecase', () {
    test('sucesso resolve em Unit', () async {
      final repo = _Repo<Unit, LogoutParameters, LogoutError>(
        const Success(unit),
      );

      final r = await LogoutUsecase(repository: repo)(logoutParams);

      expect(r, const Success<Unit, LogoutError>(unit));
    });

    test('erro do repositório sobe como erro do usecase', () async {
      final repo = _Repo<Unit, LogoutParameters, LogoutError>(
        const Failure(LogoutIndisponivel()),
      );

      expect(
        ((await LogoutUsecase(repository: repo)(logoutParams)) as Failure)
            .error,
        isA<LogoutIndisponivel>(),
      );
    });

    test('repositório fora do contrato cai em onUnexpected', () async {
      final usecase = LogoutUsecase(
        repository: _RepoQueLanca<Unit, LogoutParameters, LogoutError>(),
      );

      expect(
        ((await usecase(logoutParams)) as Failure).error,
        isA<LogoutInesperado>(),
      );
    });
  });
}
