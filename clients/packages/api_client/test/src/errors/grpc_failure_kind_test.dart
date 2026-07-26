import 'package:api_client/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classificarFalhaGrpc', () {
    test('mapeia cada status code tratado para a sua natureza', () {
      final esperado = <int, GrpcFailureKind>{
        StatusCode.unauthenticated: GrpcFailureKind.unauthenticated,
        StatusCode.permissionDenied: GrpcFailureKind.permissionDenied,
        StatusCode.invalidArgument: GrpcFailureKind.invalidArgument,
        StatusCode.failedPrecondition: GrpcFailureKind.failedPrecondition,
        StatusCode.notFound: GrpcFailureKind.notFound,
        StatusCode.alreadyExists: GrpcFailureKind.alreadyExists,
        StatusCode.resourceExhausted: GrpcFailureKind.rateLimited,
        StatusCode.unavailable: GrpcFailureKind.unavailable,
        StatusCode.deadlineExceeded: GrpcFailureKind.unavailable,
        StatusCode.cancelled: GrpcFailureKind.unavailable,
      };

      esperado.forEach((code, kind) {
        expect(
          classificarFalhaGrpc(GrpcError.custom(code, 'erro $code')),
          kind,
          reason: 'status code $code deveria classificar como $kind',
        );
      });
    });

    test('status code não tratado cai em unknown', () {
      expect(
        classificarFalhaGrpc(GrpcError.custom(StatusCode.internal, 'boom')),
        GrpcFailureKind.unknown,
      );
      expect(
        classificarFalhaGrpc(GrpcError.custom(StatusCode.dataLoss, 'boom')),
        GrpcFailureKind.unknown,
      );
    });

    test('exceção que não vem do transporte cai em unknown', () {
      // O RepositoryBase captura qualquer exceção do datasource, inclusive as do
      // mapeamento proto->modelo. Nada disso pode virar palpite de status.
      expect(
        classificarFalhaGrpc(const FormatException('json invalido')),
        GrpcFailureKind.unknown,
      );
      expect(classificarFalhaGrpc(StateError('bug')), GrpcFailureKind.unknown);
      expect(classificarFalhaGrpc('string crua'), GrpcFailureKind.unknown);
    });

    test('a mensagem do servidor não influencia a classificação', () {
      // A mensagem é chave de i18n do servidor (ex.: errors.auth) e pode mudar;
      // classificar por texto seria acoplamento frágil.
      expect(
        classificarFalhaGrpc(
          GrpcError.custom(StatusCode.unavailable, 'errors.qualquer.coisa'),
        ),
        GrpcFailureKind.unavailable,
      );
    });
  });
}
