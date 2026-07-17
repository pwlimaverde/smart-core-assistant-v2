import 'package:grpc/grpc.dart';

import 'generated/queries/auth.pbgrpc.dart';
import 'generated/queries/admin.pbgrpc.dart';
import 'grpc_transport.dart';
import 'interceptors/auth_token_interceptor.dart';

/// Transporte gRPC real do desktop (`dart:io`) — análogo ao `grpc_api_client.dart`
/// (gRPC-Web), mas para nativo.
///
/// Usa `ClientChannel` de `package:grpc/grpc.dart`, que abre sockets HTTP/2 de
/// verdade (não depende de `package:web`/`dart:js_interop`, logo compila fora do
/// browser). Os stubs [AuthServiceClient]/[AdminServiceClient] são os mesmos do
/// lado web — só o canal muda. NÃO loga token/credenciais; apenas endpoint/status.
final class GrpcNativeApiClient implements GrpcTransport {
  final String _host;
  final int _port;
  final bool _enableLogging;
  late final ClientChannel _channel;
  late final AuthServiceClient _auth;
  late final AdminServiceClient _admin;

  /// [endpoint] é o endereço da fachada (pode vir como `https://host`,
  /// `tcp://host:porta`, `http://host:porta` ou `host:porta`); [readAccessToken]
  /// devolve o access token atual (memória) para o interceptor.
  ///
  /// TLS segue o esquema do endpoint: `https` → canal seguro (porta padrão 443);
  /// demais → texto claro (porta padrão 80). Sem isso, o desktop apontado para o
  /// endpoint público (https) tentaria HTTP/2 em claro na porta 80 contra o edge
  /// TLS e nunca conectaria.
  GrpcNativeApiClient({
    required String endpoint,
    required Future<String?> Function() readAccessToken,
    bool enableLogging = false,
  })  : _host = _extrairHost(endpoint),
        _port = _extrairPorta(endpoint),
        // ignore: prefer_initializing_formals
        _enableLogging = enableLogging {
    _channel = ClientChannel(
      _host,
      port: _port,
      options: ChannelOptions(
        credentials: _usaTls(endpoint)
            ? const ChannelCredentials.secure()
            : const ChannelCredentials.insecure(),
      ),
    );
    _auth = AuthServiceClient(
      _channel,
      interceptors: [AuthTokenInterceptor(readAccessToken)],
    );
    _admin = AdminServiceClient(
      _channel,
      interceptors: [AuthTokenInterceptor(readAccessToken)],
    );
  }

  @override
  AuthServiceClient get auth => _auth;

  @override
  AdminServiceClient get admin => _admin;

  @override
  Future<void> connect() async {
    // gRPC não tem handshake explícito; o canal conecta sob demanda.
    if (_enableLogging) {
      // ignore: avoid_print
      print('GrpcNativeApiClient.connect → host=$_host port=$_port status=ready');
    }
  }

  /// Extrai o host de um endpoint que pode vir com esquema (`tcp://`, `http://`)
  /// ou como `host:porta` puro.
  static String _extrairHost(String endpoint) {
    final uri = _parse(endpoint);
    return uri.host.isNotEmpty ? uri.host : 'localhost';
  }

  /// Extrai a porta; quando ausente assume a padrão do esquema (443 para
  /// `https`, 80 para os demais).
  static int _extrairPorta(String endpoint) {
    final uri = _parse(endpoint);
    if (uri.hasPort) return uri.port;
    return _usaTls(endpoint) ? 443 : 80;
  }

  /// TLS quando o esquema do endpoint é `https`.
  static bool _usaTls(String endpoint) => _parse(endpoint).scheme == 'https';

  static Uri _parse(String endpoint) {
    final uri = Uri.parse(endpoint);
    // `host:porta` sem esquema é interpretado pelo Uri como scheme=host — força
    // um esquema neutro para extrair host/porta corretamente.
    if (uri.host.isEmpty) return Uri.parse('tcp://$endpoint');
    return uri;
  }
}
