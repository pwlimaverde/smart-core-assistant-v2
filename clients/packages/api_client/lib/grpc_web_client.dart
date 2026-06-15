/// Entrypoint do cliente gRPC-Web concreto.
///
/// Separado do barrel principal porque `GrpcApiClient` importa
/// `package:grpc/grpc_web.dart` (→ `package:web`/`dart:js_interop`), que só
/// compila em web/WASM. Importe-o apenas em código que roda no browser
/// (composição do app/`login_module`); os testes de VM usam o barrel neutro.
library;

export 'src/grpc_api_client.dart';
