import 'package:app_config/app_config.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // P2a — player de áudio/vídeo da bolha (ver main_dev.dart).
  MediaKit.ensureInitialized();
  await bootstrap(_config, updateFeedUrl: _updateFeedUrl);
}

// D6 — feed do Velopack do canal stable. O build do instalador repassa o
// mesmo valor por --dart-define; o padrão cobre builds feitos à mão.
const _updateFeedUrl = String.fromEnvironment(
  'SMARTCORE_UPDATE_FEED_URL',
  defaultValue: 'https://releases.smartcoreassistant.com.br/feed/stable',
);

const _config = AppConfig(
  flavor: AppFlavor.prod,
  apiEndpoint: String.fromEnvironment('SMARTCORE_API_ENDPOINT'),
  mcpEndpoint: String.fromEnvironment(
    'SMARTCORE_MCP_ENDPOINT',
    defaultValue: 'https://mcp.smartcoreassistant.com.br/mcp',
  ),
  // O caminho base entra aqui: o app é servido sob `/v2/…`, e não na raiz.
  // Um link montado sobre o `apiEndpoint` (que atende no domínio raiz) sai
  // do app e devolve HTTP 400 — foi o que aconteceu com o convite.
  appPublicUrl: String.fromEnvironment(
    'SMARTCORE_APP_PUBLIC_URL',
    defaultValue: 'https://smartcoreassistant.com.br/v2/tenant',
  ),
  enableLogging: false,
);
