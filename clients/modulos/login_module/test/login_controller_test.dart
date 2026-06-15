import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:login_module/src/features/login/domain/model/session.dart';
import 'package:login_module/src/features/login/domain/services/auth_service.dart';
import 'package:login_module/src/features/login/presentation/controllers/login_controller.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// AuthService fake cujo `login` devolve um resultado pré-definido.
class _FakeAuth implements AuthService {
  final ReturnSuccessOrError<Session> resultado;
  _FakeAuth(this.resultado);

  @override
  Future<ReturnSuccessOrError<Session>> login({
    required String email,
    required String password,
  }) async =>
      resultado;

  @override
  Future<ReturnSuccessOrError<Session>> refresh() async => resultado;
  @override
  Future<ReturnSuccessOrError<Unit>> logout() async =>
      const SuccessReturn(success: unit);
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
    'login feliz: emite [Loading, Success]',
    build: () =>
        LoginController(auth: _FakeAuth(SuccessReturn(success: _session()))),
    act: (c) => c.signIn('e@e.com', 'senha'),
    expect: () => [
      isA<LoadingState<Session>>(),
      isA<SuccessState<Session>>(),
    ],
  );

  blocTest<LoginController, ViewState<Session>>(
    'login com erro: emite [Loading, Error]',
    build: () => LoginController(
      auth: _FakeAuth(const ErrorReturn(error: ErrorAuth())),
    ),
    act: (c) => c.signIn('e@e.com', 'errada'),
    expect: () => [
      isA<LoadingState<Session>>(),
      isA<ErrorState<Session>>(),
    ],
  );
}
