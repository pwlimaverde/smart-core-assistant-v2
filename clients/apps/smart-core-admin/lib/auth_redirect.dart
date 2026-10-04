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
  // A recuperação de senha vem pelo `LoginModule` e é pública aqui também: o
  // superusuário esquece a senha como qualquer um.
  final rotaPublica =
      indoParaLogin ||
      location == '/recuperar-senha' ||
      location == '/redefinir-senha';
  // Sem sessão OU sem privilégio de superusuário → fora do painel admin.
  if (!isAuthenticated || !isSuperuser) return rotaPublica ? null : '/login';
  if (indoParaLogin || location == '/' || location == '/home') {
    return '/core-settings';
  }
  return null;
}

/// Links antigos do painel: até 10/2026 as rotas do `admin_module` tinham o
/// prefixo `/admin`, que somado ao `--base-href /v2/admin/` dava
/// `/v2/admin/admin/<tela>`. As rotas agora começam na raiz do app
/// (`/v2/admin/<tela>`); favoritos e links velhos são levados para o caminho
/// novo, preservando a query (`?tenantId=…`). `null` = nada a fazer.
String? legacyAdminRedirect(Uri uri) {
  final path = uri.path;
  if (path != '/admin' && !path.startsWith('/admin/')) return null;
  final novo = path.substring('/admin'.length);
  return uri.replace(path: novo.isEmpty ? '/' : novo).toString();
}
