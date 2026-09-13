import 'package:dependencies_module/dependencies_module.dart' hide AuthService;
import 'package:login_module/login_module.dart';

import '../../permissoes_de_tela.dart';

/// Escopos da sessão atual; `null` quando não há sessão conhecida.
List<String>? _escoposDaSessao() {
  if (!GetIt.instance.isRegistered<AuthService>()) return null;
  return inject<AuthService>().currentSession?.scopes;
}

/// A sessão pode usar os botões que escrevem na tela de [rota]? (B2)
///
/// Sem sessão conhecida responde `true`. Numa sessão real a tela nem abre sem
/// passar pelo guard de rota; o caso só aparece em teste de tela isolada, e
/// esconder botões ali testaria este mapa em vez da tela. A barreira continua
/// sendo o servidor.
bool sessaoPodeAlterar(String rota) {
  final escopos = _escoposDaSessao();
  return escopos == null || podeAlterarTela(escopos, rota);
}

/// Id do usuário da sessão atual (B5); `null` sem sessão ou em token antigo.
int? usuarioDaSessao() {
  if (!GetIt.instance.isRegistered<AuthService>()) return null;
  return inject<AuthService>().currentSession?.userId;
}

/// A sessão é do administrador do tenant? Mesma ressalva de [sessaoPodeAlterar].
bool sessaoEhAdmin() {
  final escopos = _escoposDaSessao();
  return escopos == null || ehAdminDoTenant(escopos);
}
