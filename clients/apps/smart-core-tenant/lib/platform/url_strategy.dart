// Seleção por import condicional: só a Web tem estratégia de URL de navegador
// (`flutter_web_plugins`, que é web-only). No desktop cai no no-op nativo.
export 'url_strategy_native.dart'
    if (dart.library.js_interop) 'url_strategy_web.dart';
