import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/evolution/data/datasources/evolution_datasources.dart';
import 'package:admin_module/src/features/evolution/data/repositories/evolution_repositories.dart';
import 'package:admin_module/src/features/evolution/domain/errors/evolution_errors.dart';
import 'package:admin_module/src/features/evolution/domain/usecases/evolution_usecases.dart';
import 'package:admin_module/src/features/evolution/domain/parameters/evolution_parameters.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `evolution`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('testEvolutionConnection', () {
    test('permissionDenied -> EvolutionAcessoNegado', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> EvolutionAcessoNegado', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> EvolutionNaoEncontrado', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionNaoEncontrado>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> EvolutionConflito', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionConflito>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> EvolutionDadosInvalidos', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> EvolutionDadosInvalidos', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> EvolutionIndisponivel', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> EvolutionIndisponivel', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> EvolutionInesperado', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> EvolutionInesperado', () async {
      when(
        () => client.testEvolutionConnection(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      );

      final r = await usecase(
        const TestEvolutionConnectionParameters(tenantId: 't1'),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<EvolutionInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as EvolutionError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
