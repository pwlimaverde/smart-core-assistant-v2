import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/ensaio_errors.dart';
import '../../domain/model/ensaio.dart';
import '../../domain/parameters/ensaio_parameters.dart';
import '../../domain/usecases/ensaio_usecases.dart';

// ignore_for_file: prefer_initializing_formals

/// Ensaio de pergunta: o que a IA responderia, e com base em quê.
final class EnsaioController extends BaseController<Ensaio> {
  final TestarPerguntaUsecase _testar;

  /// B9 (N10 E6) — opcional: sem ele a aba testa e só não pede avaliação.
  final RegistrarFeedbackTesteUsecase? _registrarFeedback;

  /// A última pergunta enviada. Guardada para a tela poder mostrá-la junto da
  /// resposta — sem isso, quem digitou uma pergunta longa perde a referência
  /// do que perguntou.
  String _ultimaPergunta = '';

  EnsaioController({
    required TestarPerguntaUsecase testar,
    RegistrarFeedbackTesteUsecase? registrarFeedback,
  }) : _testar = testar,
       _registrarFeedback = registrarFeedback;

  bool get aceitaAvaliacao => _registrarFeedback != null;

  String get ultimaPergunta => _ultimaPergunta;

  Future<void> testar(String pergunta) {
    _ultimaPergunta = pergunta;
    return execute<EnsaioError>(
      () => _testar(TestarPerguntaParameters(pergunta: pergunta)),
    );
  }

  /// B9 (N10 E6) — avalia a resposta de [ensaio] à última pergunta. Devolve o
  /// erro, ou `null` no sucesso; o resultado do teste continua na tela.
  Future<EnsaioError?> avaliar({
    required Ensaio ensaio,
    required bool boa,
    String correcao = '',
  }) async {
    final usecase = _registrarFeedback;
    if (usecase == null) return const EnsaioInesperado();
    final res = await usecase(
      RegistrarFeedbackTesteParameters(
        pergunta: _ultimaPergunta,
        respostaObtida: ensaio.resposta,
        respostaCorreta: correcao.trim(),
        boa: boa,
        comportamentoAplicado: ensaio.comportamentoAplicado,
        confiabilidade: ensaio.confiabilidade,
      ),
    );
    return switch (res) {
      Success() => null,
      Failure(:final error) => error,
    };
  }
}
