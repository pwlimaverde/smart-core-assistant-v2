import 'package:api_client/api_client.dart';
import 'package:api_client/grpc_native_client.dart';

/// Cria o transporte gRPC nativo (desktop/`dart:io`). Só compila fora do
/// browser — usa sockets HTTP/2 via `GrpcNativeApiClient`.
ApiClient createPlatformApiClient({
  required String endpoint,
  required Future<String?> Function() readAccessToken,
  required bool enableLogging,
}) =>
    GrpcNativeApiClient(
      endpoint: endpoint,
      readAccessToken: readAccessToken,
      enableLogging: enableLogging,
    );
