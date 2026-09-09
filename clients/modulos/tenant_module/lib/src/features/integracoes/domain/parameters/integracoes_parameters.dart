import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros das operações sobre aplicativos conectados (N13.8).
///
/// Listar não tem parâmetro: o backend resolve tenant **e usuário** a partir da
/// sessão, e cada pessoa só enxerga os próprios consentimentos. Não existe
/// variante "listar os do tenant" — nem para `tenant:admin`.

/// Desconexão de um aplicativo conectado.
final class RevokeMcpGrantParameters extends Parameters {
  final String grantId;

  const RevokeMcpGrantParameters({required this.grantId});
}
