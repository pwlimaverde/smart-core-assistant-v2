import 'package:meta/meta.dart';

/// Mensagem de um thread de atendimento (chat lateral — WS-6.3).
///
/// [conteudo] é PII (mensagem do usuário/atendente): a UI nunca deve logá-lo.
@immutable
final class MensagemThread {
  final int id;
  final int atendimentoId;
  final String tipo;
  final String conteudo;
  final String remetente;
  final DateTime timestamp;
  final String statusEnvio;

  const MensagemThread({
    required this.id,
    required this.atendimentoId,
    required this.tipo,
    required this.conteudo,
    required this.remetente,
    required this.timestamp,
    required this.statusEnvio,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is MensagemThread && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
