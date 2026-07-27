import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/audit/data/datasources/audit_datasources.dart';
import 'package:admin_module/src/features/audit/data/repositories/audit_repositories.dart';
import 'package:admin_module/src/features/audit/domain/errors/audit_errors.dart';
import 'package:admin_module/src/features/audit/domain/usecases/audit_usecases.dart';
import 'package:admin_module/src/features/audit/domain/parameters/audit_parameters.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `audit`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('queryAuditLog', () {
    test('permissionDenied -> AuditAcessoNegado', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> AuditAcessoNegado', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> AuditNaoEncontrado', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditNaoEncontrado>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> AuditConflito', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditConflito>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> AuditDadosInvalidos', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> AuditDadosInvalidos', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> AuditIndisponivel', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> AuditIndisponivel', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> AuditInesperado', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> AuditInesperado', () async {
      when(
        () => client.queryAuditLog(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      );

      final r = await usecase(const QueryAuditLogParameters());

      final erro = (r as Failure).error;
      expect(erro, isA<AuditInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as AuditError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
