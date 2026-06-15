import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/session.dart';

/// Usecase de login. O datasource já entrega a [Session] pronta (I/O + mapeamento),
/// então o `process` é um passthrough (D == T): repassa o sucesso.
final class LoginUsecase extends UsecaseBaseCallData<Session, Session> {
  LoginUsecase({required super.datasource});

  @override
  ProcessData<Session, Session> get process => _process;

  static ReturnSuccessOrError<Session> _process(
    Session data,
    ParametersReturnResult parameters,
  ) =>
      SuccessReturn(success: data);
}
