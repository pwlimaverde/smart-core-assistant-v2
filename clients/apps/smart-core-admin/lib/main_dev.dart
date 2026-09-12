import 'package:app_config/app_config.dart';

import 'bootstrap.dart';

void main() => bootstrap(
  const AppConfig(
    flavor: AppFlavor.dev,
    apiEndpoint: String.fromEnvironment(
      'SMARTCORE_API_ENDPOINT',
      defaultValue: 'tcp://localhost:50051',
    ),
    // O dominio de dev, e nao o de producao: a descoberta OAuth deste ambiente
    // anuncia `resource: https://mcp.dev.…`, e colar o endereco de producao
    // faria o cliente recusar por divergencia.
    mcpEndpoint: String.fromEnvironment(
      'SMARTCORE_MCP_ENDPOINT',
      defaultValue: 'https://mcp.dev.smartcoreassistant.com.br/mcp',
    ),
    // O caminho base entra aqui: o app é servido sob `/v2/…`, e não na raiz.
    // Um link montado sobre o `apiEndpoint` (que atende no domínio raiz) sai
    // do app e devolve HTTP 400 — foi o que aconteceu com o convite.
    appPublicUrl: String.fromEnvironment(
      'SMARTCORE_APP_PUBLIC_URL',
      defaultValue: 'https://dev.smartcoreassistant.com.br/v2/admin',
    ),
    enableLogging: true,
  ),
);
