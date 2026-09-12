import 'package:return_success_or_error/return_success_or_error.dart';

/// Preenchimento manual de um campo do cartão (N9 E13).
final class DefinirValorCampoParameters extends Parameters {
  final int atendimentoId;
  final int campoId;

  /// JSON na forma do tipo do campo. `"null"` apaga de propósito, que é
  /// diferente de nunca ter sido preenchido: a IA não repreenche o que alguém
  /// apagou.
  final String valorJson;

  const DefinirValorCampoParameters({
    required this.atendimentoId,
    required this.campoId,
    required this.valorJson,
  });
}
