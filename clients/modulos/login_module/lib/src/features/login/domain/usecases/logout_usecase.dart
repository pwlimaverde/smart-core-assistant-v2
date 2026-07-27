import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/auth_errors.dart';
import '../parameters/logout_parameters.dart';

/// Usecase de logout: o datasource sinaliza sucesso com [Unit] e o `process`
/// repassa.
final class LogoutUsecase
    extends UsecaseBaseCallData<Unit, Unit, LogoutParameters, LogoutError> {
  const LogoutUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, LogoutParameters, LogoutError> get process =>
      _process;

  @override
  LogoutError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log(
      'process do logout quebrou',
      name: 'login_module.logout',
      error: exception,
      stackTrace: stackTrace,
    );
    return const LogoutInesperado();
  }

  static ReturnSuccessOrError<Unit, LogoutError> _process(
    Unit data,
    LogoutParameters parameters,
  ) => const Success(unit);
}
