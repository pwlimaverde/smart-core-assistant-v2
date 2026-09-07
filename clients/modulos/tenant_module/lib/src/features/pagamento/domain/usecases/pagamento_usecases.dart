import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/pagamento_errors.dart';
import '../model/quitacao.dart';
import '../parameters/pagamento_parameters.dart';

final class QuitarAssinaturaUsecase
    extends
        UsecaseBaseCallData<
          Quitacao,
          Quitacao,
          QuitarAssinaturaParameters,
          PagamentoError
        > {
  const QuitarAssinaturaUsecase({required super.repository});

  @override
  ProcessData<Quitacao, Quitacao, QuitarAssinaturaParameters, PagamentoError>
  get process => _process;

  @override
  PagamentoError onUnexpected(Object exception, StackTrace stackTrace) {
    developer.log(
      'process de quitarAssinatura quebrou',
      name: 'tenant_module.pagamento',
      // Só o tipo da exceção: a mensagem pode carregar o parâmetro, e o
      // parâmetro aqui é uma credencial.
      error: exception.runtimeType,
      stackTrace: stackTrace,
    );
    return const PagamentoInesperado();
  }

  /// Passa o desfecho adiante como veio.
  ///
  /// **Recusa não vira erro aqui de propósito.** Código expirado ou esgotado
  /// chega como `confirmado: false` com mensagem, e a tela precisa dessa
  /// mensagem junto do campo. Traduzi-la para `Failure` a jogaria no caminho de
  /// erro genérico e perderia o motivo que o servidor deu.
  static ReturnSuccessOrError<Quitacao, PagamentoError> _process(
    Quitacao data,
    QuitarAssinaturaParameters parameters,
  ) => Success(data);
}
