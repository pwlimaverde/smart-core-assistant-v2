import 'package:return_success_or_error/return_success_or_error.dart';

/// Os campos de escrita de uma intenção, nomeados.
///
/// Um struct e não cinco strings soltas: `descricao` e `exemplo` são ambos
/// texto livre e trocá-los de lugar não daria erro de compilação nenhum.
final class DadosIntent {
  final String tag;
  final String grupo;
  final String descricao;
  final String exemplo;
  final String comportamento;

  /// Coleta do motor Jev (ver `IntentIa.camposColeta`).
  final List<String> camposColeta;
  final int maxPerguntas;
  final String aposColeta;

  const DadosIntent({
    required this.tag,
    required this.grupo,
    required this.descricao,
    required this.exemplo,
    required this.comportamento,
    this.camposColeta = const [],
    this.maxPerguntas = 2,
    this.aposColeta = 'transferir',
  });
}

final class CriarIntentParameters extends Parameters {
  final DadosIntent dados;

  const CriarIntentParameters({required this.dados});
}

final class AtualizarIntentParameters extends Parameters {
  final int id;
  final DadosIntent dados;

  const AtualizarIntentParameters({required this.id, required this.dados});
}

final class IntentIdParameters extends Parameters {
  final int id;

  const IntentIdParameters({required this.id});
}
