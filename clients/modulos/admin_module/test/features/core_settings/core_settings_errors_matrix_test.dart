import 'package:api_client/api_client.dart';
import 'package:api_client/testing.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/core_settings/data/datasources/core_settings_datasources.dart';
import 'package:admin_module/src/features/core_settings/data/repositories/core_settings_repositories.dart';
import 'package:admin_module/src/features/core_settings/domain/errors/core_settings_errors.dart';
import 'package:admin_module/src/features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'package:admin_module/src/features/core_settings/domain/parameters/core_settings_parameters.dart';

import '../../support/admin_grpc_mock.dart';

/// Matriz de tradução de erro da feature `core_settings`.
///
/// As operações da feature compartilham um `mapError`. Este teste é o que
/// garante que compartilhar não escondeu um caso no braço errado: cada
/// operação é exercitada contra as dez naturezas de falha possíveis.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('listCoreSettings', () {
    test('permissionDenied -> CoreSettingsAcessoNegado', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> CoreSettingsAcessoNegado', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> CoreSettingsNaoEncontrado', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsNaoEncontrado>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> CoreSettingsConflito', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsConflito>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> CoreSettingsDadosInvalidos', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> CoreSettingsDadosInvalidos', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> CoreSettingsIndisponivel', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> CoreSettingsIndisponivel', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> CoreSettingsInesperado', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> CoreSettingsInesperado', () async {
      when(
        () => client.listCoreSettings(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      );

      final r = await usecase(noParams);

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('upsertCoreSetting', () {
    test('permissionDenied -> CoreSettingsAcessoNegado', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> CoreSettingsAcessoNegado', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> CoreSettingsNaoEncontrado', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsNaoEncontrado>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> CoreSettingsConflito', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsConflito>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> CoreSettingsDadosInvalidos', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> CoreSettingsDadosInvalidos', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> CoreSettingsIndisponivel', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> CoreSettingsIndisponivel', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> CoreSettingsInesperado', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> CoreSettingsInesperado', () async {
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(
        const UpsertCoreSettingParameters(
          key: 'k',
          value: 'v',
          encrypted: false,
          description: 'd',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });

  group('deleteCoreSetting', () {
    test('permissionDenied -> CoreSettingsAcessoNegado', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unauthenticated -> CoreSettingsAcessoNegado', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unauthenticated('sem sessao')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('notFound -> CoreSettingsNaoEncontrado', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.notFound('inexistente')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsNaoEncontrado>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('alreadyExists -> CoreSettingsConflito', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.alreadyExists('duplicado')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsConflito>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('invalidArgument -> CoreSettingsDadosInvalidos', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.invalidArgument('invalido')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('failedPrecondition -> CoreSettingsDadosInvalidos', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.failedPrecondition('estado')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('unavailable -> CoreSettingsIndisponivel', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.unavailable('offline')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('resourceExhausted -> CoreSettingsIndisponivel', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.resourceExhausted('quota')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsIndisponivel>());
      expect(erro, isA<NetworkFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('internal (não tratado) -> CoreSettingsInesperado', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.internal('boom')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });

    test('exceção fora do transporte -> CoreSettingsInesperado', () async {
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(const FormatException('json')));
      final usecase = DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      );

      final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

      final erro = (r as Failure).error;
      expect(erro, isA<CoreSettingsInesperado>());
      expect(erro, isA<UnexpectedFailure>());
      expect(
        (erro as CoreSettingsError).message,
        isNot(contains('boom')),
        reason: 'a mensagem exibida não repete o texto da exceção',
      );
    });
  });
}
