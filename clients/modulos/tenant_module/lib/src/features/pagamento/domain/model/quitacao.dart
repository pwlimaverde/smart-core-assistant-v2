import 'package:meta/meta.dart';

/// Desfecho de uma tentativa de quitar a assinatura já logado.
///
/// **Recusa não é erro.** Código expirado, já usado ou inexistente são
/// resultados de negócio: o servidor responde sucesso com [confirmado] falso e
/// uma mensagem, e a tela a mostra junto do campo. Erro de RPC fica reservado
/// para falha de verdade (rede fora, sessão inválida, sem permissão).
@immutable
final class Quitacao {
  /// `true` = assinatura ativa ao fim da chamada, inclusive se já estava.
  final bool confirmado;

  /// `ACTIVE`, `PENDING_PAYMENT`, `SUSPENDED`… Vazio = sem assinatura.
  final String assinaturaStatus;

  /// Preenchida quando o provedor exige concluir o pagamento fora do app.
  /// Vazia para voucher.
  final String urlExterna;

  /// Motivo legível por máquina (`codigo_vazio`, `expirado`, `esgotado`…).
  final String motivo;

  /// Mensagem para mostrar junto do campo. Vazia quando confirmou.
  final String erroLegivel;

  const Quitacao({
    required this.confirmado,
    this.assinaturaStatus = '',
    this.urlExterna = '',
    this.motivo = '',
    this.erroLegivel = '',
  });

  /// O provedor pede para concluir fora do app.
  bool get exigeSaidaDoApp => !confirmado && urlExterna.isNotEmpty;

  /// Recusa de negócio: há o que dizer ao usuário no próprio campo.
  bool get recusado => !confirmado && urlExterna.isEmpty;
}
