import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/ensaio_errors.dart';
import '../model/ensaio.dart';
import '../parameters/ensaio_parameters.dart';

final class TestarPerguntaUsecase extends UsecaseBaseCallData<Ensaio, Ensaio,
    TestarPerguntaParameters, EnsaioError> {
  const TestarPerguntaUsecase({required super.repository});

  /// Ordena os trechos do mais parecido para o menos.
  ///
  /// O servidor já devolve nessa ordem, mas quem lê a tela precisa poder
  /// confiar nela para julgar o resultado — e a ordenação é regra de
  /// apresentação, não da consulta.
  @override
  ProcessData<Ensaio, Ensaio, TestarPerguntaParameters, EnsaioError>
      get process => (data, _) => Success(
            Ensaio(
              resposta: data.resposta,
              comportamentoAplicado: data.comportamentoAplicado,
              trechos: List.of(data.trechos)
                ..sort((a, b) => a.distancia.compareTo(b.distancia)),
              confiabilidade: data.confiabilidade,
              transferiria: data.transferiria,
              fluxoTransferencia: data.fluxoTransferencia,
            ),
          );

  @override
  EnsaioError onUnexpected(Object e, StackTrace s) {
    developer.log(
      'testar pergunta: exceção fora da fronteira',
      name: 'treinamento_module.ensaio.usecase',
      error: e,
      stackTrace: s,
    );
    return const EnsaioInesperado();
  }
}
