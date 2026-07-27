import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/tenant_config/data/datasources/tenant_config_datasources.dart';
import 'package:admin_module/src/features/tenant_config/data/repositories/tenant_config_repositories.dart';
import 'package:admin_module/src/features/tenant_config/domain/errors/tenant_config_errors.dart';
import 'package:admin_module/src/features/tenant_config/domain/usecases/tenant_config_usecases.dart';
import 'package:admin_module/src/features/tenant_config/domain/parameters/tenant_config_parameters.dart';

import '../../support/admin_grpc_mock.dart';
import '../../support/fixtures.dart';

/// Matriz de tradução de erro da feature `tenant_config`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('getTenantConfig', () {
    test('permissionDenied -> TenantConfigAcessoNegado', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantConfigAcessoNegado', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantConfigNaoEncontrado', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigNaoEncontrado>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantConfigConflito', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigConflito>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantConfigDadosInvalidos', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantConfigDadosInvalidos', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantConfigIndisponivel', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantConfigIndisponivel', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantConfigInesperado', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantConfigInesperado', () async {
      when(
        () => client.getTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(const GetTenantConfigParameters(tenantId: 't1'));

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('updateTenantConfig', () {
    test('permissionDenied -> TenantConfigAcessoNegado', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> TenantConfigAcessoNegado', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> TenantConfigNaoEncontrado', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigNaoEncontrado>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> TenantConfigConflito', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigConflito>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> TenantConfigDadosInvalidos', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> TenantConfigDadosInvalidos', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> TenantConfigIndisponivel', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> TenantConfigIndisponivel', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> TenantConfigInesperado', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> TenantConfigInesperado', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: client),
        ),
      );

      final r = await usecase(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<TenantConfigInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as TenantConfigError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
