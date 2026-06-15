import 'package:return_success_or_error/return_success_or_error.dart';

/// Usecase de logout. O datasource sinaliza sucesso via [Unit]; o `process`
/// repassa (D == T == Unit).
final class LogoutUsecase extends UsecaseBaseCallData<Unit, Unit> {
  LogoutUsecase({required super.datasource});

  @override
  ProcessData<Unit, Unit> get process => _process;

  static ReturnSuccessOrError<Unit> _process(
    Unit data,
    ParametersReturnResult parameters,
  ) =>
      const SuccessReturn(success: unit);
}
