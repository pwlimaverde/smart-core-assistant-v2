import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros da quitação da assinatura pelo dono, já logado.
///
/// **Não carrega `tenant_id`**: o backend resolve o tenant a partir das claims.
/// Aceitar um tenant vindo do cliente seria deixar alguém quitar (ou consultar)
/// a assinatura de outro.
final class QuitarAssinaturaParameters extends Parameters {
  /// `id` do provedor. Hoje só `voucher`.
  final String provedor;

  /// O que o dono digitou. Para voucher, o código.
  ///
  /// **É credencial**: não vai para log, nem para span, nem para a trilha de
  /// auditoria — um código de campanha vale enquanto tiver resgates.
  final String credencial;

  const QuitarAssinaturaParameters({
    required this.provedor,
    required this.credencial,
  });
}
