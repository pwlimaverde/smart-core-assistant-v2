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

/// Recorte da aba "Atividade" (B3).
///
/// Não carrega usuário nem tenant: quem não é admin vê só o que os próprios
/// agentes fizeram, e esse recorte é imposto pelo servidor — um parâmetro aqui
/// seria só uma promessa que o cliente poderia quebrar.
final class ListarAtividadeParameters extends Parameters {
  /// `true` = só o que foi feito por aplicativos conectados.
  final bool soAgentes;

  /// Restringe a um aplicativo; `null` = todos.
  final String? grantId;

  /// Só o que aconteceu a partir daqui; `null` = sem limite.
  final DateTime? desde;

  const ListarAtividadeParameters({
    this.soAgentes = true,
    this.grantId,
    this.desde,
  });
}
