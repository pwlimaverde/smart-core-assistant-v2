import 'package:api_client/api_client.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/grpc_error_mapper.dart';

void main() {
  group('mapGrpcError (operacional_module)', () {
    const fallback = ErrorNetwork();

    test('unauthenticated → ErrorUnauthorized', () {
      expect(
        mapGrpcError(GrpcError.unauthenticated('x'), fallback),
        isA<ErrorUnauthorized>(),
      );
    });

    test(
      'permissionDenied → ErrorUnauthorized (cobre RBAC fino de fluxo, WS-5a)',
      () {
        final err = mapGrpcError(GrpcError.permissionDenied('x'), fallback);
        expect(err, isA<ErrorUnauthorized>());
        expect((err as ErrorUnauthorized).message, 'Acesso negado.');
      },
    );

    test('invalidArgument → ErrorValidation', () {
      expect(
        mapGrpcError(GrpcError.invalidArgument('x'), fallback),
        isA<ErrorValidation>(),
      );
    });

    test('unavailable/deadlineExceeded → ErrorNetwork', () {
      expect(
        mapGrpcError(GrpcError.unavailable('x'), fallback),
        isA<ErrorNetwork>(),
      );
      expect(
        mapGrpcError(GrpcError.deadlineExceeded('x'), fallback),
        isA<ErrorNetwork>(),
      );
    });

    test('código não mapeado → fallback', () {
      expect(mapGrpcError(GrpcError.internal('x'), fallback), fallback);
    });
  });
}
