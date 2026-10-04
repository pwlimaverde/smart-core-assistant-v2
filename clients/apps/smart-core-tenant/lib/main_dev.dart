import 'package:app_config/app_config.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // P2a — player de áudio/vídeo da bolha. Só inicializa o backend; o libmpv
  // é carregado quando a primeira bolha cria um `Player`. Na Web é no-op
  // prático (usa o <video> do navegador).
  MediaKit.ensureInitialized();
  await bootstrap(_config, updateFeedUrl: _updateFeedUrl);
}

// D6 — feed do Velopack do canal beta. O build do instalador repassa o
// mesmo valor por --dart-define; o padrão cobre builds feitos à mão.
const _updateFeedUrl = String.fromEnvironment(
  'SMARTCORE_UPDATE_FEED_URL',
  defaultValue: 'https://releases.smartcoreassistant.com.br/feed/beta',
);

const _config = AppConfig(
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
    defaultValue: 'https://dev.smartcoreassistant.com.br/v2/tenant',
  ),
  enableLogging: true,
);
