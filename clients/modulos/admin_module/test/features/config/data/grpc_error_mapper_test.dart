import 'package:admin_module/src/features/config/data/grpc_error_mapper.dart';
import 'package:api_client/api_client.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';

// O mapGrpcError traduz cada StatusCode gRPC da borda para um AppError tipado de
// domínio. Aqui exercitamos cada ramo do switch, garantindo tanto o tipo do erro
// quanto (onde relevante) a mensagem customizada. O ramo default devolve o
// fallback recebido sem transformacao.
void main() {
  const fallback = ErrorNetwork(message: 'fallback');

  group('mapGrpcError', () {
    test('unauthenticated -> ErrorUnauthorized', () {
      final result = mapGrpcError(const GrpcError.unauthenticated(), fallback);
      expect(result, isA<ErrorUnauthorized>());
    });

    test('permissionDenied -> ErrorUnauthorized com mensagem "Acesso negado."', () {
      final result = mapGrpcError(const GrpcError.permissionDenied(), fallback);
      expect(result, isA<ErrorUnauthorized>());
      expect(result.message, 'Acesso negado.');
    });

    test('invalidArgument -> ErrorValidation', () {
      final result = mapGrpcError(const GrpcError.invalidArgument(), fallback);
      expect(result, isA<ErrorValidation>());
    });

    test('resourceExhausted -> ErrorAuth com aviso de rate limit', () {
      final result = mapGrpcError(const GrpcError.resourceExhausted(), fallback);
      expect(result, isA<ErrorAuth>());
      expect(result.message, contains('Muitas tentativas'));
    });

    test('unavailable -> ErrorNetwork', () {
      final result = mapGrpcError(const GrpcError.unavailable(), fallback);
      expect(result, isA<ErrorNetwork>());
    });

    test('deadlineExceeded -> ErrorNetwork', () {
      final result = mapGrpcError(const GrpcError.deadlineExceeded(), fallback);
      expect(result, isA<ErrorNetwork>());
    });

    test('codigo nao mapeado (ex.: notFound) -> devolve o fallback recebido', () {
      final result = mapGrpcError(const GrpcError.notFound(), fallback);
      expect(result, same(fallback));
    });

    test('outro codigo nao mapeado (internal) -> tambem devolve o fallback', () {
      const outroFallback = ErrorValidation(message: 'padrao');
      final result = mapGrpcError(const GrpcError.internal(), outroFallback);
      expect(result, same(outroFallback));
    });
  });
}
