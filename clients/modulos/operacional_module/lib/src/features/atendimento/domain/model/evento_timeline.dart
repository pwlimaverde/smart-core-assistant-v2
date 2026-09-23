import 'package:meta/meta.dart';

/// P5 — um acontecimento da vida do atendimento.
///
/// A [descricao] chega pronta do servidor (é ele que sabe juntar "etapa A →
/// etapa B" ou o texto da nota). Pode conter conteúdo do cliente: a tela
/// exibe, nunca loga.
@immutable
final class EventoDaTimeline {
  /// `aberto`, `movido`, `nota`, `etiqueta`, `avaliado` ou `encerrado`.
  final String tipo;
  final DateTime quando;
  final String descricao;

  /// Vazio quando foi o sistema ou a IA.
  final String autor;
  final bool automatico;

  const EventoDaTimeline({
    required this.tipo,
    required this.quando,
    required this.descricao,
    this.autor = '',
    this.automatico = false,
  });
}
