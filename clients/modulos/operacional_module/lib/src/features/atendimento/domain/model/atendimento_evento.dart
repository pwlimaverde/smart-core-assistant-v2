import 'package:meta/meta.dart';

/// Evento realtime recebido do `StreamAtendimentos` (WS-6.3).
///
/// Espelha o `AtendimentoEvent` do contrato (`event_type`/`tenant_id`/`payload`
/// JSON) já decodificado para um mapa Dart. O `payload` nunca deve ser logado
/// em claro (pode carregar conteúdo de mensagem — PII).
@immutable
final class AtendimentoEvento {
  final String tipo;
  final String tenantId;
  final Map<String, Object?> payload;

  const AtendimentoEvento({
    required this.tipo,
    required this.tenantId,
    required this.payload,
  });

  /// `atendimento_id` presente no payload, quando houver (a maioria dos
  /// eventos operacionais carrega este campo).
  int? get atendimentoId {
    final v = payload['atendimento_id'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return null;
  }
}
