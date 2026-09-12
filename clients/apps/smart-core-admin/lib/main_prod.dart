import 'package:app_config/app_config.dart';

import 'bootstrap.dart';

void main() => bootstrap(
  const AppConfig(
    flavor: AppFlavor.prod,
    apiEndpoint: String.fromEnvironment('SMARTCORE_API_ENDPOINT'),
    mcpEndpoint: String.fromEnvironment(
      'SMARTCORE_MCP_ENDPOINT',
      defaultValue: 'https://mcp.smartcoreassistant.com.br/mcp',
    ),
    enableLogging: false,
  ),
);
