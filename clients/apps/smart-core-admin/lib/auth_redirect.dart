/// Decisão pura do guard de rota (boot + autenticação), isolada de qualquer
/// dependência de UI/DI/transporte para ser testável na VM:
///  - durante o boot, mantém tudo na splash '/';
///  - após o boot, exige sessão: deslogado → '/login'; logado → sai do login
///    e da splash para '/home'; demais rotas seguem.
String? authRedirectTarget({
  required bool booted,
  required bool isAuthenticated,
  required String location,
}) {
  if (!booted) return location == '/' ? null : '/';

  final indoParaLogin = location == '/login';
  if (!isAuthenticated) return indoParaLogin ? null : '/login';
  if (indoParaLogin || location == '/' || location == '/home') return '/admin/core-settings';
  return null;
}
