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
    final withAuth = options.mergedWith(
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
    return invoker(method, request, withAuth);
  }

  @override
  ResponseStream<R> interceptStreaming<Q, R>(
    ClientMethod<Q, R> method,
    Stream<Q> requests,
    CallOptions options,
    ClientStreamingInvoker<Q, R> invoker,
  ) {
    // Sem streaming no escopo do login; repassa sem alteração.
    return invoker(method, requests, options);
  }
}
