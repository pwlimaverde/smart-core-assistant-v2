import 'package:meta/meta.dart';

/// Um aplicativo de IA conectado ao tenant por OAuth 2.1 (N13).
///
/// **[clientName] é texto de terceiro.** Ele vem do Client ID Metadata Document
/// que o próprio cliente publica, e nada impede que diga "Smart Core Oficial".
/// É por isso que a tela mostra sempre o [redirectHost] ao lado: o nome é
/// escolhido por quem se conecta, o host é o endereço para onde o acesso volta —
/// e é esse que o usuário consegue reconhecer ou estranhar.
@immutable
class McpGrant {
  final String id;

  /// URL do Client ID Metadata Document. Na spec MCP, é o identificador do
  /// cliente — não existe registro prévio de aplicativo.
  final String clientId;

  /// Nome exibido, declarado pelo próprio cliente. NÃO confiável.
  final String clientName;

  /// URI completa de retorno. A tela mostra só o host.
  final String redirectUri;

  /// Escopos concedidos, no vocabulário do backend (`atendimentos:write`).
  /// A tradução para linguagem de negócio é da camada de apresentação.
  final List<String> scopes;

  /// `null` quando o aplicativo nunca chamou nada desde que foi conectado.
  final DateTime? lastUsedAt;

  final DateTime createdAt;

  const McpGrant({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.redirectUri,
    required this.scopes,
    required this.lastUsedAt,
    required this.createdAt,
  });

  /// Host do `redirect_uri` — o que o usuário precisa reconhecer.
  ///
  /// Em caso de URI malformada devolve a string inteira: melhor mostrar algo
  /// estranho do que esconder o destino.
  String get redirectHost {
    final uri = Uri.tryParse(redirectUri);
    if (uri == null || uri.host.isEmpty) return redirectUri;
    return uri.host;
  }

  /// `true` quando o aplicativo só devolve o acesso para a própria máquina do
  /// usuário — típico de programa instalado. A tela sinaliza isso.
  bool get ehLocal =>
      const {'localhost', '127.0.0.1', '::1'}.contains(redirectHost);

  /// `true` se algum escopo concedido permite alterar dados.
  ///
  /// A tela usa isto para destacar as conexões que podem escrever: a diferença
  /// entre um agente que só lê e um que envia mensagem a cliente é a informação
  /// mais importante desta lista.
  bool get podeAlterar => scopes.any(
    (s) => s == 'tenant:admin' || s.endsWith(':write') || s.endsWith(':admin'),
  );
}
