import 'package:grpc/service_api.dart';

/// Interceptor de cliente gRPC que injeta o access token no metadata
/// `authorization: Bearer <token>` de cada chamada.
///
/// IMPORTANTE (assinatura síncrona): `interceptUnary` retorna `ResponseFuture<R>`
/// sem `await`. Por isso o token é resolvido por um **provider assíncrono** via
/// `CallOptions(providers: [...])`, que roda no momento da chamada e enxerga o
/// valor atual (inclusive logo após um refresh). O retry-após-refresh **NÃO**
/// acontece aqui — é orquestrado no `AuthServiceImpl` (single-flight).
final class AuthTokenInterceptor implements ClientInterceptor {
  final Future<String?> Function() _readAccessToken;

  AuthTokenInterceptor(this._readAccessToken);

  @override
  ResponseFuture<R> interceptUnary<Q, R>(
    ClientMethod<Q, R> method,
    Q request,
    CallOptions options,
    ClientUnaryInvoker<Q, R> invoker,
  ) {
    return invoker(method, request, _comToken(options));
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    // O stream precisa do token tanto quanto a chamada unária. Repassar sem ele
    // fazia o `StreamAtendimentos` ser recusado sempre ("stream.nao_autorizado"
    // na auditoria): o quadro nunca recebia evento em tempo real e só se
    // atualizava recarregando. O provider roda a cada abertura, então a
    // reconexão depois de um refresh já sai com o token novo.
    return invoker(method, requests, _comToken(options));
  }

  CallOptions _comToken(CallOptions options) => options.mergedWith(
    CallOptions(
      providers: [
        (metadata, _) async {
          final token = await _readAccessToken();
          if (token != null && token.isNotEmpty) {
            metadata['authorization'] = 'Bearer $token';
          }
        },
      ],
    ),
  );
}
