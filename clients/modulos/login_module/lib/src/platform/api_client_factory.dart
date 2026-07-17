// Seleção de plataforma por import condicional: web usa gRPC-Web (arrasta
// `package:web`/`dart:js_interop`), nativo/desktop usa sockets HTTP/2 (`dart:io`).
// O condicional `dart.library.js_interop` é verdadeiro apenas em web (JS e WASM),
// então o desktop cai na implementação nativa e o import web-only nunca compila lá.
//
// Ambas as implementações expõem `createPlatformApiClient({endpoint,
// readAccessToken, enableLogging})` devolvendo um `GrpcTransport` (auth/admin).
export 'api_client_factory_native.dart'
    if (dart.library.js_interop) 'api_client_factory_web.dart';
