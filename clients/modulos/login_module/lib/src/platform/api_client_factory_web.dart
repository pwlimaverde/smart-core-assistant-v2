import 'package:api_client/api_client.dart';
import 'package:api_client/grpc_web_client.dart';

/// Cria o transporte gRPC-Web (browser). Só compila em web — arrasta
/// `package:web`/`dart:js_interop` via `GrpcApiClient`.
ApiClient createPlatformApiClient({
  required String endpoint,
  required Future<String?> Function() readAccessToken,
  required bool enableLogging,
}) => GrpcApiClient(
  endpoint: endpoint,
  readAccessToken: readAccessToken,
  enableLogging: enableLogging,
);
