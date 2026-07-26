/// Suporte a testes da borda gRPC — **não importe em código de produção**.
///
/// Vive dentro do `api_client` porque é aqui que o detalhe do transporte mora:
/// os stubs gerados devolvem `ResponseFuture`, um `Future` com `headers`,
/// `trailers` e `cancel`, que não se constrói sem um `ClientCall` real. Sem este
/// arquivo, cada módulo que quisesse testar o próprio datasource contra um stub
/// falso reescreveria o mesmo adaptador — foi assim que os quatro
/// `grpc_error_mapper.dart` duplicados apareceram.
library;

import 'package:async/async.dart';
import 'package:grpc/grpc.dart';

/// `ResponseFuture` de mentira: delega a um [Future] comum e devolve metadados
/// vazios.
final class FakeResponseFuture<R> extends DelegatingFuture<R>
    implements ResponseFuture<R> {
  FakeResponseFuture(super.future);

  @override
  Future<Map<String, String>> get headers async => const {};

  @override
  Future<Map<String, String>> get trailers async => const {};

  @override
  Future<void> cancel() async {}
}

/// Resposta de sucesso para um stub mockado:
/// `when(() => client.login(any())).thenAnswer((_) => respostaGrpc(resp))`.
ResponseFuture<R> respostaGrpc<R>(R valor) =>
    FakeResponseFuture<R>(Future<R>.value(valor));

/// Falha para um stub mockado — aceita [GrpcError] ou qualquer exceção, para
/// exercitar também o caminho "não veio do transporte" do `mapError`.
ResponseFuture<R> falhaGrpc<R>(Object erro) =>
    FakeResponseFuture<R>(Future<R>.error(erro));
