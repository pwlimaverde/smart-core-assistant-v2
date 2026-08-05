import 'package:return_success_or_error/return_success_or_error.dart';

final class AtendimentoIdParameters extends Parameters {
  final int atendimentoId;

  const AtendimentoIdParameters({required this.atendimentoId});
}

final class CriarEtiquetaParameters extends Parameters {
  final String nome;
  final String cor;

  const CriarEtiquetaParameters({required this.nome, required this.cor});
}

final class AlternarEtiquetaParameters extends Parameters {
  final int atendimentoId;
  final int etiquetaId;

  /// `false` tira a etiqueta da conversa.
  final bool aplicar;

  const AlternarEtiquetaParameters({
    required this.atendimentoId,
    required this.etiquetaId,
    required this.aplicar,
  });
}

final class CriarNotaParameters extends Parameters {
  final int atendimentoId;
  final String texto;

  const CriarNotaParameters({required this.atendimentoId, required this.texto});
}
