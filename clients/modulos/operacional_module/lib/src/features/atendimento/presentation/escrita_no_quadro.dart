import 'package:dependencies_module/dependencies_module.dart' show GetIt;

/// P16 — quem está logado pode escrever no atendimento?
///
/// O servidor já recusa (N13.3), mas a tela oferecia enviar, mover e atribuir a
/// quem só pode ler — e a recusa chegava como erro depois do clique. A pergunta
/// vem pronta do app hospedeiro, pelo mesmo motivo do menu: a sessão é do
/// `login_module`, e este módulo não a conhece.
final class EscritaNoQuadro {
  final bool Function() _pode;

  const EscritaNoQuadro(this._pode);

  bool get pode => _pode();
}

/// Sem registro (testes de tela, app antigo) a resposta é "pode": esconder os
/// botões testaria o mapa de permissão em vez da tela. A barreira é o servidor.
bool quadroPodeEscrever() {
  final getIt = GetIt.instance;
  if (!getIt.isRegistered<EscritaNoQuadro>()) return true;
  return getIt<EscritaNoQuadro>().pode;
}
