enum AppFlavor { dev, staging, prod }

/// Configuração imutável do app, injetada no escopo global no boot.
final class AppConfig {
  final AppFlavor flavor;
  final String apiEndpoint;

  /// Endereço do servidor MCP mostrado na tela de aplicativos conectados.
  ///
  /// Precisa vir por ambiente, e não como constante na tela: o documento de
  /// descoberta OAuth (`/.well-known/oauth-protected-resource`) declara o
  /// `resource` com o domínio **daquele** ambiente, e um cliente que valide o
  /// casamento recusa a conexão quando o endereço colado não é o mesmo. Foi o
  /// que aconteceu ao apontar o app de dev para o domínio de produção: os dois
  /// respondem, mas a descoberta anunciava `mcp.dev.` e a conexão não fecharia.
  final String mcpEndpoint;

  /// Onde este app é servido, para montar links que saem dele.
  ///
  /// **Não é o `apiEndpoint`.** O gRPC atende no domínio raiz, mas o app web do
  /// tenant é servido sob `/v2/tenant/` — e um link montado sobre o endpoint da
  /// API aponta para fora do app: foi o que fez o convite chegar por e-mail com
  /// um endereço que devolvia HTTP 400.
  ///
  /// Inclui o caminho base quando há um, e nunca termina em barra.
  final String appPublicUrl;

  final bool enableLogging;

  const AppConfig({
    required this.flavor,
    required this.apiEndpoint,
    required this.mcpEndpoint,
    required this.appPublicUrl,
    this.enableLogging = false,
  });

  bool get isProd => flavor == AppFlavor.prod;
}
