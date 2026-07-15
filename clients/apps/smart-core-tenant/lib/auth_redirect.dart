/// Decisão pura do guard de rota (boot + autenticação + persona de tenant),
/// isolada de qualquer dependência de UI/DI/transporte para ser testável na VM:
///  - durante o boot, mantém tudo na splash '/';
///  - `/login` e `/aceitar-convite` são rotas públicas (a segunda é o fluxo de
///    aceite de convite, acessado por quem ainda não tem conta/sessão);
///  - exige sessão de TENANT: deslogado → '/login'; um superusuário puro (sem
///    `tenant_id`) não pertence a nenhum tenant e é tratado como não
///    autorizado aqui — este app é exclusivo de sessões de tenant, o painel do
///    superusuário é o `smart-core-admin` (defesa em profundidade — a fachada
///    gRPC-Web também recusa via `exigir_autenticado_do_metadata`/escopo);
///  - logado como tenant: sai do login/splash para o workspace ('/atendimentos');
///    demais rotas seguem;
///  - RBAC de UI: rotas administrativas ('/tenant/*' — convites/usuários/
///    config) exigem o escopo `tenant:admin` (ou `*`) na sessão; sem ele,
///    volta para o workspace (defesa em profundidade — o backend já barra e
///    audita por escopo em cada RPC).
String? tenantAuthRedirectTarget({
  required bool booted,
  required bool isAuthenticated,
  required bool isSuperuser,
  required List<String> scopes,
  required String location,
}) {
  if (!booted) return location == '/' ? null : '/';

  final rotaPublica = location == '/login' || location == '/aceitar-convite';
  // Sem sessão OU superusuário puro (sem tenant) → fora do painel do tenant.
  if (!isAuthenticated || isSuperuser) {
    return rotaPublica ? null : '/login';
  }
  if (location == '/login' || location == '/' || location == '/home') {
    return '/atendimentos';
  }
  final isTenantAdmin = scopes.contains('tenant:admin') || scopes.contains('*');
  if (location.startsWith('/tenant/') && !isTenantAdmin) {
    return '/atendimentos';
  }
  return null;
}
