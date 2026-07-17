/// Entrypoint do cliente gRPC nativo concreto (desktop/`dart:io`).
///
/// Separado do barrel principal porque `GrpcNativeApiClient` importa
/// `package:grpc/grpc.dart` (→ sockets HTTP/2 de `dart:io`), que só compila
/// fora do browser. Importe-o apenas em código que roda no desktop (composição
/// do app via import condicional); no browser usa-se `grpc_web_client.dart`.
library;

export 'src/grpc_native_api_client.dart';
