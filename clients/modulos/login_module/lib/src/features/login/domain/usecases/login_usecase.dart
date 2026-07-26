import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/auth_errors.dart';
import '../model/session.dart';
import '../parameters/login_parameters.dart';

/// Usecase de login.
///
/// O repositório entrega a [Session] pronta, então o `process` é passthrough
/// (`TData == TValue`). Não é código morto: é o ponto onde entraria uma regra de
/// negócio de cliente (rejeitar sessão sem escopo, exigir troca de senha), e é
/// o que garante que uma exceção no caminho caia em [onUnexpected] em vez de
/// escapar para o controller.
final class LoginUsecase
    extends UsecaseBaseCallData<Session, Session, LoginParameters, LoginError> {
  const LoginUsecase({required super.repository});

  @override
  ProcessData<Session, Session, LoginParameters, LoginError> get process =>
      _process;

  @override
  LoginError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log(
      'process do login quebrou',
      name: 'login_module.login',
      error: exception,
      stackTrace: stackTrace,
    );
    return const LoginInesperado();
  }

  static ReturnSuccessOrError<Session, LoginError> _process(
    Session data,
    LoginParameters parameters,
  ) => Success(data);
}
