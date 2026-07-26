import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/auth_errors.dart';
import '../model/session.dart';
import '../parameters/refresh_parameters.dart';

/// Usecase de refresh: o repositório entrega a [Session] rotacionada e o
/// `process` repassa.
final class RefreshTokenUsecase
    extends
        UsecaseBaseCallData<Session, Session, RefreshParameters, RefreshError> {
  const RefreshTokenUsecase({required super.repository});

  @override
  ProcessData<Session, Session, RefreshParameters, RefreshError> get process =>
      _process;

  @override
  RefreshError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log(
      'process do refresh quebrou',
      name: 'login_module.refresh',
      error: exception,
      stackTrace: stackTrace,
    );
    return const RefreshInesperado();
  }

  static ReturnSuccessOrError<Session, RefreshError> _process(
    Session data,
    RefreshParameters parameters,
  ) => Success(data);
}
