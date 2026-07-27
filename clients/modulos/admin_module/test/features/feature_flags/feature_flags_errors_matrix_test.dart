import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/feature_flags/data/datasources/feature_flags_datasources.dart';
import 'package:admin_module/src/features/feature_flags/data/repositories/feature_flags_repositories.dart';
import 'package:admin_module/src/features/feature_flags/domain/errors/feature_flags_errors.dart';
import 'package:admin_module/src/features/feature_flags/domain/usecases/feature_flags_usecases.dart';
import 'package:admin_module/src/features/feature_flags/domain/parameters/feature_flags_parameters.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `feature_flags`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('listFeatureFlags', () {
    test('permissionDenied -> FeatureFlagsAcessoNegado', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> FeatureFlagsAcessoNegado', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> FeatureFlagsNaoEncontrado', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsNaoEncontrado>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> FeatureFlagsConflito', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsConflito>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> FeatureFlagsDadosInvalidos', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> FeatureFlagsDadosInvalidos', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> FeatureFlagsIndisponivel', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> FeatureFlagsIndisponivel', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> FeatureFlagsInesperado', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> FeatureFlagsInesperado', () async {
      when(
        () => client.listFeatureFlags(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('setFeatureFlag', () {
    test('permissionDenied -> FeatureFlagsAcessoNegado', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> FeatureFlagsAcessoNegado', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> FeatureFlagsNaoEncontrado', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsNaoEncontrado>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> FeatureFlagsConflito', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsConflito>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> FeatureFlagsDadosInvalidos', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> FeatureFlagsDadosInvalidos', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> FeatureFlagsIndisponivel', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> FeatureFlagsIndisponivel', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> FeatureFlagsInesperado', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> FeatureFlagsInesperado', () async {
      when(
        () => client.setFeatureFlag(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('setFeatureFlagOverride', () {
    test('permissionDenied -> FeatureFlagsAcessoNegado', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> FeatureFlagsAcessoNegado', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> FeatureFlagsNaoEncontrado', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsNaoEncontrado>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> FeatureFlagsConflito', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsConflito>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> FeatureFlagsDadosInvalidos', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> FeatureFlagsDadosInvalidos', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> FeatureFlagsIndisponivel', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> FeatureFlagsIndisponivel', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> FeatureFlagsInesperado', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> FeatureFlagsInesperado', () async {
      when(
        () => client.setFeatureFlagOverride(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      );

      final r = await usecase(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: true,
          removeOverride: false,
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<FeatureFlagsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as FeatureFlagsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
