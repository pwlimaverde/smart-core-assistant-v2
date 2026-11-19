// Seleção por import condicional, como em `api_client_factory.dart`: a Web usa
// a Web Locks API (`navigator.locks`); o desktop roda um processo só e não
// precisa de trava entre instâncias.
export 'trava_entre_abas_native.dart'
    if (dart.library.js_interop) 'trava_entre_abas_web.dart';
