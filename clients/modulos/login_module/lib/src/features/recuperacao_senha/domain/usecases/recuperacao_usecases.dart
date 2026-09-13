import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/recuperacao_errors.dart';
import '../parameters/recuperacao_parameters.dart';

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'login_module.recuperacao_senha',
      error: exception,
      stackTrace: stackTrace,
    );

final class SolicitarRedefinicaoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          SolicitarRedefinicaoParameters,
          SolicitarRedefinicaoError
        > {
  const SolicitarRedefinicaoUsecase({required super.repository});

  @override
  ProcessData<
    Unit,
    Unit,
    SolicitarRedefinicaoParameters,
    SolicitarRedefinicaoError
  >
  get process => _process;

  @override
  SolicitarRedefinicaoError onUnexpected(
    Object exception,
    StackTrace stackTrace,
  ) {
    _logBug('solicitarRedefinicao', exception, stackTrace);
    return const SolicitarRedefinicaoInesperado();
  }

  static ReturnSuccessOrError<Unit, SolicitarRedefinicaoError> _process(
    Unit data,
    SolicitarRedefinicaoParameters parameters,
  ) => const Success(unit);
}

final class RedefinirSenhaUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          RedefinirSenhaParameters,
          RedefinirSenhaError
        > {
  const RedefinirSenhaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, RedefinirSenhaParameters, RedefinirSenhaError>
  get process => _process;

  @override
  RedefinirSenhaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('redefinirSenha', exception, stackTrace);
    return const RedefinirSenhaInesperado();
  }

  static ReturnSuccessOrError<Unit, RedefinirSenhaError> _process(
    Unit data,
    RedefinirSenhaParameters parameters,
  ) => const Success(unit);
}
