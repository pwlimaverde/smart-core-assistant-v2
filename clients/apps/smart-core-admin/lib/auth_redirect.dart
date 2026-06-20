/// Decisão pura do guard de rota (boot + autenticação + superusuário), isolada de
/// qualquer dependência de UI/DI/transporte para ser testável na VM:
///  - durante o boot, mantém tudo na splash '/';
///  - após o boot, exige sessão: deslogado → '/login';
///  - exige superusuário: este painel é exclusivo do superadmin; uma sessão comum
///    (sem `is_superuser`) é tratada como não autorizada e volta para '/login'
///    (defesa em profundidade — a fachada gRPC-Web também recusa via
///    `exigir_superuser_do_metadata`);
///  - logado e superusuário: sai do login e da splash para o painel; demais rotas seguem.
String? authRedirectTarget({
  required bool booted,
  required bool isAuthenticated,
  required bool isSuperuser,
  required String location,
}) {
  if (!booted) return location == '/' ? null : '/';

  final indoParaLogin = location == '/login';
  // Sem sessão OU sem privilégio de superusuário → fora do painel admin.
  if (!isAuthenticated || !isSuperuser) return indoParaLogin ? null : '/login';
  if (indoParaLogin || location == '/' || location == '/home') return '/admin/core-settings';
  return null;
}
