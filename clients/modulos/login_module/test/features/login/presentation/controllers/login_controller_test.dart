import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/domain/errors/auth_errors.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/services/auth_service.dart';
import 'package:login_module/src/features/login/presentation/controllers/login_controller.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// AuthService falso: devolve o resultado combinado e registra o que recebeu.
class _FakeAuth implements AuthService {
  final ReturnSuccessOrError<Session, LoginError> resultadoLogin;
  String? emailRecebido;
  String? senhaRecebida;

  _FakeAuth(this.resultadoLogin);

  @override
  Future<ReturnSuccessOrError<Session, LoginError>> login({
    required String email,
    required String password,
  }) async {
    emailRecebido = email;
    senhaRecebida = password;
    return resultadoLogin;
  }

  @override
  Future<ReturnSuccessOrError<Session, RefreshError>> refresh() async =>
      const Failure(SemSessaoPersistida());
  @override
  Future<ReturnSuccessOrError<Unit, LogoutError>> logout() async =>
      const Success(unit);
  @override
  bool get isAuthenticated => false;
  @override
  Session? get currentSession => null;
  @override
  Listenable get authChanges => ValueNotifier<int>(0);
}

Session _session() => Session(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(minutes: 15)),
  tenantId: 't',
  scopes: const [],
  isSuperuser: false,
);

void main() {
  blocTest<LoginController, ViewState<Session>>(
    'login feliz: emite [Loading, Success] com a sessão',
    build: () => LoginController(auth: _FakeAuth(Success(_session()))),
    act: (c) => c.signIn('e@e.com', 'senha'),
    expect: () => [
      isA<LoadingState<Session>>(),
      isA<SuccessState<Session>>().having(
        (s) => s.data.accessToken,
        'accessToken',
        'a',
      ),
    ],
  );

  blocTest<LoginController, ViewState<Session>>(
    'credenciais inválidas: emite [Loading, Error] com o caso concreto',
    build: () =>
        LoginController(auth: _FakeAuth(const Failure(CredenciaisInvalidas()))),
    act: (c) => c.signIn('e@e.com', 'errada'),
    expect: () => [
      isA<LoadingState<Session>>(),
      isA<ErrorState<Session>>().having(
        (s) => s.error,
        'erro',
        isA<CredenciaisInvalidas>(),
      ),
    ],
  );

  blocTest<LoginController, ViewState<Session>>(
    'rate limit chega à tela com a mensagem da feature',
    build: () => LoginController(
      auth: _FakeAuth(const Failure(LoginBloqueadoPorTentativas())),
    ),
    act: (c) => c.signIn('e@e.com', 'senha'),
    expect: () => [
      isA<LoadingState<Session>>(),
      isA<ErrorState<Session>>().having(
        (s) => ErrorMessageMapper.map(s.error),
        'mensagem exibida',
        contains('Muitas tentativas'),
      ),
    ],
  );

  blocTest<LoginController, ViewState<Session>>(
    'erro inesperado é exibido de forma genérica',
    build: () =>
        LoginController(auth: _FakeAuth(const Failure(LoginInesperado()))),
    act: (c) => c.signIn('e@e.com', 'senha'),
    expect: () => [
      isA<LoadingState<Session>>(),
      isA<ErrorState<Session>>().having(
        (s) => ErrorMessageMapper.map(s.error),
        'mensagem exibida',
        ErrorMessageMapper.mensagemGenerica,
      ),
    ],
  );

  test('repassa e-mail e senha ao serviço sem alterá-los', () async {
    final auth = _FakeAuth(Success(_session()));
    final controller = LoginController(auth: auth);

    await controller.signIn(' e@e.com ', 'senha com espaço');

    expect(auth.emailRecebido, ' e@e.com ');
    expect(auth.senhaRecebida, 'senha com espaço');
    await controller.close();
  });
}
