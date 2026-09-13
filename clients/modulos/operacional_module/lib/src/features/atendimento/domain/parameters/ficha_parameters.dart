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

/// D3 — liga/desliga a resposta automática da IA nesta conversa.
final class DefinirBotDaConversaParameters extends Parameters {
  final int atendimentoId;
  final bool habilitado;

  const DefinirBotDaConversaParameters({
    required this.atendimentoId,
    required this.habilitado,
  });
}

/// B6 (N9 E4) — marca como lidas as mensagens do contato numa conversa.
final class MarcarAtendimentoLidoParameters extends Parameters {
  final int atendimentoId;

  const MarcarAtendimentoLidoParameters({required this.atendimentoId});
}

final class CriarNotaParameters extends Parameters {
  final int atendimentoId;
  final String texto;

  const CriarNotaParameters({required this.atendimentoId, required this.texto});
}
