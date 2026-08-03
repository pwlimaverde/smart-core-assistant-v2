import 'package:return_success_or_error/return_success_or_error.dart';

/// Cria um material de treinamento.
final class CriarTreinamentoParameters extends Parameters {
  final String tag;
  final String grupo;
  final String conteudo;

  const CriarTreinamentoParameters({
    required this.tag,
    required this.grupo,
    required this.conteudo,
  });
}

/// Identifica um treinamento — usado por consulta e remoção.
final class TreinamentoIdParameters extends Parameters {
  final int id;

  const TreinamentoIdParameters({required this.id});
}

/// Aceita a revisão: grava o texto e envia para a IA processar.
final class FinalizarTreinamentoParameters extends Parameters {
  final int id;
  final String conteudo;

  const FinalizarTreinamentoParameters({
    required this.id,
    required this.conteudo,
  });
}
