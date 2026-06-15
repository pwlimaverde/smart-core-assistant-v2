// Superfície NEUTRA (compila em VM e web): contrato, stubs gerados, interceptor
// e os tipos de erro/status do gRPC. O cliente concreto de transporte gRPC-Web
// (`GrpcApiClient`, que arrasta `package:web`) fica em `grpc_web_client.dart`,
// importado só por quem roda no browser (app/login_module), nunca pelos testes VM.
//
// ignore_for_file: implementation_imports
export 'src/api_client.dart';
export 'src/interceptors/auth_token_interceptor.dart';

// Stubs gerados do auth.proto (mensagens + AuthServiceClient). Usam apenas
// `service_api.dart`/`protobuf` — neutros.
export 'src/generated/queries/auth.pbgrpc.dart';

// Tipos usados pelos datasources/mapper. `CallOptions` vem do service_api;
// `GrpcError`/`StatusCode` de `status.dart` (puro: dart:convert/protobuf) —
// neutros, ao contrário de `grpc_web.dart`, que arrasta `package:web`.
export 'package:grpc/service_api.dart' show CallOptions;
export 'package:grpc/src/shared/status.dart' show GrpcError, StatusCode;
