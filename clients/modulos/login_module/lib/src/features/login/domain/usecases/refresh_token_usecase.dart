import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/session.dart';

/// Usecase de refresh. Passthrough (D == T): o datasource entrega a [Session]
/// rotacionada e o `process` repassa o sucesso.
final class RefreshTokenUsecase extends UsecaseBaseCallData<Session, Session> {
  RefreshTokenUsecase({required super.datasource});

  @override
  ProcessData<Session, Session> get process => _process;

  static ReturnSuccessOrError<Session> _process(
    Session data,
    ParametersReturnResult parameters,
  ) =>
      SuccessReturn(success: data);
}
