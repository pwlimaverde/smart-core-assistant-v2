import 'package:onboarding_module/onboarding_module.dart'
    show ehRotaDeCadastro, ehRotaDeConfiguracao, rotaDeConfiguracaoDoPasso;

/// Decisão pura do guard de rota (boot + autenticação + persona de tenant),
/// isolada de qualquer dependência de UI/DI/transporte para ser testável na VM:
///  - durante o boot, mantém tudo na splash '/';
///  - `/login`, `/aceitar-convite` e `/cadastro*` são rotas públicas (a segunda
///    é o aceite de convite; a terceira é o wizard de criação de conta — ambas
///    acessadas por quem ainda não tem conta/sessão);
///  - exige sessão de TENANT: deslogado → '/login'; um superusuário puro (sem
///    `tenant_id`) não pertence a nenhum tenant e é tratado como não
///    autorizado aqui — este app é exclusivo de sessões de tenant, o painel do
///    superusuário é o `smart-core-admin` (defesa em profundidade — a fachada
///    gRPC-Web também recusa via `exigir_autenticado_do_metadata`/escopo);
///  - logado como tenant: sai do login/splash para o workspace ('/atendimentos');
///    demais rotas seguem;
///  - RBAC de UI: rotas administrativas ('/tenant/*' e '/conta/pagamento' —
///    convites/usuários/config/cobrança) exigem o escopo `tenant:admin` (ou
///    `*`) na sessão; sem ele, volta para o workspace (defesa em profundidade —
///    o backend já barra e audita por escopo em cada RPC).
///
/// **Ordem de precedência**, do mais forte para o mais fraco: boot → sessão →
/// **pagamento** → roteiro de configuração → workspace. O pagamento vir antes do
/// roteiro é o que corrige o beco sem saída: com a ordem invertida, quem tem a
/// conta pendente é levado a '/configuracao/pronto' e fica sem tela para
/// resolver.
String? tenantAuthRedirectTarget({
  required bool booted,
  required bool isAuthenticated,
  required bool isSuperuser,
  required List<String> scopes,
  required String location,
  // Endereço pedido por inteiro, com a query. Só serve para ser guardado na ida
  // para a splash — `location` não tem a query, e é nela que o convite leva o
  // token.
  String? enderecoPedido,
  // Destino guardado na ida para a splash (`/?retomar=…`).
  String? retomar,
  // `null` = ainda não se sabe se a configuração inicial terminou. Ver
  // `PortaoConfiguracao`: o guard é síncrono e a verdade está no servidor.
  bool? onboardingPendente,
  int onboardingPasso = 5,
  // Tri-estado, igual ao acima: `null` = ainda não se sabe.
  bool? pagamentoPendente,
}) {
  // Durante o boot tudo espera na splash — mas o endereço pedido vai junto.
  //
  // Antes ia só '/', e o destino se perdia: quem abria o link do convite
  // (`/aceitar-convite?token=…`) terminava o boot em '/', que para quem não
  // tem sessão é '/login'. A tela de criar a senha nunca aparecia.
  if (!booted) {
    if (location == '/') return null;
    return Uri(
      path: '/',
      queryParameters: {'retomar': enderecoPedido ?? location},
    ).toString();
  }

  // Boot concluído com um destino guardado: decide por ele, como se tivesse
  // sido pedido agora — e as regras de sessão continuam valendo para ele.
  final destino = _destinoInterno(retomar);
  if (location == '/' && destino != null) {
    final alvo = tenantAuthRedirectTarget(
      booted: true,
      isAuthenticated: isAuthenticated,
      isSuperuser: isSuperuser,
      scopes: scopes,
      location: Uri.parse(destino).path,
      onboardingPendente: onboardingPendente,
      onboardingPasso: onboardingPasso,
      pagamentoPendente: pagamentoPendente,
    );
    // '/' é "ainda não sei" (a consulta do roteiro não voltou): fica na
    // splash com o destino guardado, em vez de soltá-lo.
    if (alvo == '/') return null;
    return alvo ?? destino;
  }

  final rotaPublica =
      location == '/login' ||
      location == '/aceitar-convite' ||
      ehRotaDeCadastro(location);
  // Sem sessão OU superusuário puro (sem tenant) → fora do painel do tenant.
  if (!isAuthenticated || isSuperuser) {
    return rotaPublica ? null : '/login';
  }

  // Regra espelhada de `scopesGrantTenantAdmin`/`Session.isTenantAdmin`
  // (login_module). NÃO importamos aquele predicado aqui de propósito: este
  // guard é puro/testável na VM e não pode arrastar o transporte (grpc-web)
  // que o barrel do login_module traz junto.
  final isTenantAdmin = scopes.contains('tenant:admin') || scopes.contains('*');

  // Pagamento pendente tem precedência sobre TUDO — inclusive sobre o roteiro.
  //
  // A ordem é o cerne da correção. Antes, o roteiro vencia: um tenant cuja
  // sessão expirou no meio do wizard voltava a logar e ia direto para
  // '/configuracao/pronto' — a tela que diz "tudo certo" para quem não pode
  // cadastrar nada. Toda escrita esbarrava em "assinatura inadimplente" e não
  // havia rota que resolvesse: a tela de pagamento do wizard é pública e
  // depende de um `signup_token` que morreu com a sessão.
  //
  // Duas exceções, ambas necessárias:
  //  - a própria rota de pagamento, senão o guard entra em laço;
  //  - **quem não é dono**. Cobrança é assunto do dono; mandar um colaborador
  //    para uma tela que o RBAC logo abaixo devolve produziria exatamente o
  //    laço que a primeira exceção evita. Para ele o caminho é o aviso de
  //    pendência no quadro, com "fale com o responsável".
  if (isTenantAdmin &&
      location != '/conta/pagamento' &&
      pagamentoPendente == true) {
    return '/conta/pagamento';
  }

  // Configuração inicial inacabada tem precedência sobre o workspace.
  //
  // Sem isto, quem fechava o app no meio do roteiro reabria em '/atendimentos'
  // — tela vazia, sem WhatsApp conectado e sem caminho de volta: a conta ficava
  // paga e inutilizável. O progresso vive no servidor exatamente para
  // sobreviver ao fechamento do programa.
  if (!ehRotaDeConfiguracao(location)) {
    // Enquanto a consulta não responde, segura na splash: mandar para o
    // workspace e corrigir depois faria a tela piscar.
    if (onboardingPendente == null) return location == '/' ? null : '/';
    if (onboardingPendente) return rotaDeConfiguracaoDoPasso(onboardingPasso);
  }

  if (location == '/login' || location == '/' || location == '/home') {
    return '/atendimentos';
  }
  if (location.startsWith('/tenant/') && !isTenantAdmin) {
    return '/atendimentos';
  }
  // Cobrança é assunto do dono. Um colaborador não vê valor, plano nem campo de
  // voucher — para ele o aviso de pendência diz "fale com o responsável".
  // Defesa em profundidade: o `QuitarMinhaAssinatura` também exige
  // `tenant:admin` e o `data_postgres` revalida.
  if (location == '/conta/pagamento' && !isTenantAdmin) {
    return '/atendimentos';
  }
  return null;
}

/// Só caminhos deste app: `retomar` vem da URL, e aceitar `//outro.site` ou um
/// endereço absoluto faria do guard um redirecionador aberto.
String? _destinoInterno(String? retomar) {
  if (retomar == null || retomar == '/') return null;
  if (!retomar.startsWith('/') || retomar.startsWith('//')) return null;
  return retomar;
}
