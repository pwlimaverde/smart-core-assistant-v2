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
    enableLogging: true,
  ),
);
