import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros para enviar uma mensagem outbound do atendente (chat — WS-6.3).
///
/// [conteudo] é PII: nunca deve ser logado pela UI (só trafega no corpo da
/// chamada RPC, nunca em `print`/`debugPrint`/eventos de auditoria do cliente).
final class SendOutboundMessageParameters extends Parameters {
  final int atendimentoId;
  final String conteudo;
  final String tipo;

  const SendOutboundMessageParameters({
    required this.atendimentoId,
    required this.conteudo,
    this.tipo = 'texto',
  });
}
