import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/evolution_errors.dart';
import '../model/evolution_connection_result.dart';
import '../parameters/evolution_parameters.dart';

/// Casos de uso da feature `evolution`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.evolution',
      error: exception,
      stackTrace: stackTrace,
    );

/// Testa a conexão da instância WhatsApp de um tenant.
final class TestEvolutionConnectionUsecase
    extends
        UsecaseBaseCallData<
          EvolutionConnectionResult,
          EvolutionConnectionResult,
          TestEvolutionConnectionParameters,
          EvolutionError
        > {
  const TestEvolutionConnectionUsecase({required super.repository});

  @override
  ProcessData<
    EvolutionConnectionResult,
    EvolutionConnectionResult,
    TestEvolutionConnectionParameters,
    EvolutionError
  >
  get process => _process;

  @override
  EvolutionError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('testEvolutionConnection', exception, stackTrace);
    return const EvolutionInesperado();
  }

  static ReturnSuccessOrError<EvolutionConnectionResult, EvolutionError>
  _process(
    EvolutionConnectionResult data,
    TestEvolutionConnectionParameters parameters,
  ) => Success(data);
}
