/// Quem pode abrir e quem pode alterar cada tela do painel do tenant (B2).
///
/// Espelho do `rbac::MAPA` do `runtime_api`, do lado da tela. **Não é a
/// barreira** — a barreira é o servidor, que recusa a chamada. Isto existe para
/// não oferecer à pessoa um caminho que termina em "sem permissão", que é a pior
/// forma de comunicar uma restrição.
///
/// Sem import nenhum, de propósito: o guard de rota do app importa este arquivo
/// direto e precisa continuar testável na VM, sem arrastar o transporte gRPC.
/// O teste `permissoes_de_tela_test.dart` lê o `rbac.rs` e falha se os dois
/// lados divergirem.
library;

/// Lista vazia = **só** o administrador do tenant — a mesma leitura do
/// `SOMENTE_ADMIN` do servidor. Nunca "qualquer um".
const List<String> somenteAdmin = <String>[];

/// Escopos que abrem cada tela; basta um. `null` = qualquer sessão de tenant.
///
/// O escopo é o da chamada que a tela faz **ao abrir**, e não um escolhido para
/// o menu: uma tela visível cuja primeira chamada o servidor recusa abriria
/// direto no erro.
const Map<String, List<String>?> escoposParaAbrir = {
  // GetPainelTenant
  '/tenant/painel': ['atendimentos:read'],
  // ListContatos — quem atende também procura o cliente para abrir conversa.
  '/tenant/contatos': ['clientes:read', 'atendimentos:read'],
  // ListClientes — o cadastro de negócio por trás dos contatos (B10).
  '/tenant/clientes': ['clientes:read'],
  // ListDepartamentos e ListAtendentes
  '/tenant/equipe': ['operacional:read'],
  // ListFluxos
  '/tenant/fluxos': ['atendimentos:read'],
  // ListCamposPersonalizados
  '/tenant/campos': ['configuracoes:read'],
  // ListWhatsappInstances
  '/tenant/conexoes': ['operacional:read'],
  // ListNumerosIgnorados — quem lê o quadro precisa poder descobrir por que uma
  // conversa nunca aparece nele.
  '/tenant/ignorados': ['operacional:read'],
  // ListTreinamentos
  '/tenant/treinamento': ['treinamento:read'],
  '/tenant/convites': somenteAdmin,
  '/tenant/usuarios': somenteAdmin,
  // GetMyTenantConfig
  '/tenant/config': ['configuracoes:read'],
  // Os aplicativos de IA conectados são de cada pessoa (N13.8): esconder a
  // tela deixaria alguém sem meio de desconectar um agente que ele autorizou.
  '/tenant/integracoes': null,
};

/// Escopos para os botões que escrevem em cada tela; basta um.
///
/// Tela ausente aqui não tem botão de escrita separado da abertura (convites e
/// usuários já são só do admin; aplicativos conectados são da própria pessoa).
const Map<String, List<String>> escoposParaAlterar = {
  '/tenant/contatos': ['clientes:write'],
  '/tenant/clientes': ['clientes:write'],
  '/tenant/equipe': ['operacional:admin'],
  '/tenant/fluxos': ['kanban:admin'],
  '/tenant/campos': ['configuracoes:write'],
  '/tenant/conexoes': ['operacional:admin'],
  '/tenant/ignorados': ['operacional:admin'],
  '/tenant/treinamento': ['treinamento:write'],
  '/tenant/config': ['configuracoes:write'],
};

/// A mesma regra do `rbac::autorizado`: `tenant:admin` e o coringa `*`
/// satisfazem tudo; fora isso, basta um dos exigidos. Lista vazia é só admin.
bool escoposSatisfazem(List<String> daSessao, List<String>? exigidos) {
  if (exigidos == null) return true;
  if (daSessao.contains('*') || daSessao.contains('tenant:admin')) return true;
  return exigidos.any(daSessao.contains);
}

/// Só o administrador do tenant.
bool ehAdminDoTenant(List<String> escopos) =>
    escoposSatisfazem(escopos, somenteAdmin);

/// A seção de [location]: a própria rota ou aquela de que ela é subtela —
/// `/tenant/fluxos/3/etapas` é Fluxos. `null` quando não é tela declarada.
String? secaoDe(String location, Iterable<String> rotas) {
  String? achada;
  for (final rota in rotas) {
    final pertence = location == rota || location.startsWith('$rota/');
    if (pertence && (achada == null || rota.length > achada.length)) {
      achada = rota;
    }
  }
  return achada;
}

/// `true` quando a sessão pode abrir a tela em [location].
bool podeAbrirTela(List<String> escopos, String location) {
  final secao = secaoDe(location, escoposParaAbrir.keys);
  if (secao != null) {
    return escoposSatisfazem(escopos, escoposParaAbrir[secao]);
  }
  // Tela nova sob `/tenant/` que ninguém declarou fica só para o admin —
  // fail-closed, como a rota não declarada no servidor.
  if (location.startsWith('/tenant/')) return ehAdminDoTenant(escopos);
  return true;
}

/// `true` quando a sessão pode usar os botões que escrevem na tela [location].
bool podeAlterarTela(List<String> escopos, String location) {
  final secao = secaoDe(location, escoposParaAlterar.keys);
  if (secao == null) return podeAbrirTela(escopos, location);
  return escoposSatisfazem(escopos, escoposParaAlterar[secao]);
}
