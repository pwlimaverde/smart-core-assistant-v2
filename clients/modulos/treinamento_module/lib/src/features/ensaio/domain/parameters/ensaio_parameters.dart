import 'package:return_success_or_error/return_success_or_error.dart';

final class TestarPerguntaParameters extends Parameters {
  final String pergunta;

  const TestarPerguntaParameters({required this.pergunta});
}

/// B9 (N10 E6) — a avaliação de um ensaio.
final class RegistrarFeedbackTesteParameters extends Parameters {
  final String pergunta;
  final String respostaObtida;

  /// Como a IA deveria ter respondido. Vazio = só avaliou.
  final String respostaCorreta;
  final bool boa;
  final String comportamentoAplicado;
  final double confiabilidade;

  const RegistrarFeedbackTesteParameters({
    required this.pergunta,
    required this.respostaObtida,
    required this.respostaCorreta,
    required this.boa,
    required this.comportamentoAplicado,
    required this.confiabilidade,
  });
}

/// P17 — tira a avaliação da revisão.
final class TratarAvaliacaoParameters extends Parameters {
  final int id;

  /// `true` = a correção virou material de treinamento; `false` = dispensada.
  final bool virouTreinamento;

  const TratarAvaliacaoParameters({
    required this.id,
    required this.virouTreinamento,
  });
}
