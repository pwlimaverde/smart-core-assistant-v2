import 'package:grpc/grpc_web.dart';

import 'api_client.dart';
import 'generated/queries/auth.pbgrpc.dart';
import 'interceptors/auth_token_interceptor.dart';

/// Cliente gRPC-Web real da borda de autenticação.
///
/// Cria o canal gRPC-Web (`GrpcWebClientChannel.xhr`) — que no `grpc` 4.x usa
/// `package:web`/`dart:js_interop` (compatível com `flutter build web --wasm`)
/// — e expõe o stub [AuthServiceClient] com o [AuthTokenInterceptor] já
/// acoplado. NÃO loga token/credenciais; apenas endpoint/status.
final class GrpcApiClient implements ApiClient {
  final Uri _uri;
  final bool _enableLogging;
  late final GrpcWebClientChannel _channel;
  late final AuthServiceClient _auth;

  /// [endpoint] é a URL HTTP(S) da fachada (mesma origem do WASM, via Caddy).
  /// [readAccessToken] devolve o access token atual (memória) para o interceptor.
  GrpcApiClient({
    required String endpoint,
    required Future<String?> Function() readAccessToken,
    bool enableLogging = false,
  })  : _uri = _normalizarEndpoint(endpoint),
        _enableLogging = enableLogging {
    _channel = GrpcWebClientChannel.xhr(_uri);
    _auth = AuthServiceClient(
      _channel,
      interceptors: [AuthTokenInterceptor(readAccessToken)],
    );
  }

  /// Stub do `AuthService` para os datasources do `login_module`.
  AuthServiceClient get auth => _auth;

  @override
  Future<void> connect() async {
    // gRPC-Web não tem handshake explícito; o canal conecta sob demanda.
    if (_enableLogging) {
      // ignore: avoid_print
      print('GrpcApiClient.connect → endpoint=$_uri status=ready');
    }
  }

  /// Coage o endpoint para um esquema HTTP(S) válido para gRPC-Web.
  ///
  /// O `apiEndpoint` da base pode vir como `tcp://host:porta` (convenção do
  /// transporte interno); o browser fala HTTP, então normalizamos o esquema.
  static Uri _normalizarEndpoint(String endpoint) {
    final uri = Uri.parse(endpoint);
    if (uri.scheme == 'http' || uri.scheme == 'https') return uri;
    return uri.replace(scheme: 'http');
  }
}
