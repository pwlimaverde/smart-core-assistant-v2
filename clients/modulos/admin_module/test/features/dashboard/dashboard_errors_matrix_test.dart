import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/dashboard/data/datasources/dashboard_datasources.dart';
import 'package:admin_module/src/features/dashboard/data/repositories/dashboard_repositories.dart';
import 'package:admin_module/src/features/dashboard/domain/errors/dashboard_errors.dart';
import 'package:admin_module/src/features/dashboard/domain/usecases/dashboard_usecases.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `dashboard`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('getServiceHealth', () {
    test('permissionDenied -> DashboardAcessoNegado', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> DashboardAcessoNegado', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> DashboardNaoEncontrado', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardNaoEncontrado>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> DashboardConflito', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardConflito>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> DashboardDadosInvalidos', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> DashboardDadosInvalidos', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> DashboardIndisponivel', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> DashboardIndisponivel', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> DashboardInesperado', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> DashboardInesperado', () async {
      when(
        () => client.getServiceHealth(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('getDashboardSummary', () {
    test('permissionDenied -> DashboardAcessoNegado', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> DashboardAcessoNegado', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> DashboardNaoEncontrado', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardNaoEncontrado>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> DashboardConflito', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardConflito>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> DashboardDadosInvalidos', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> DashboardDadosInvalidos', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> DashboardIndisponivel', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> DashboardIndisponivel', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> DashboardInesperado', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> DashboardInesperado', () async {
      when(
        () => client.getDashboardSummary(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<DashboardInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as DashboardError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
