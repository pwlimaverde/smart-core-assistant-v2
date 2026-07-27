import 'package:admin_module/src/features/core_settings/data/datasources/core_settings_datasources.dart';
import 'package:admin_module/src/features/core_settings/data/repositories/core_settings_repositories.dart';
import 'package:admin_module/src/features/core_settings/domain/errors/core_settings_errors.dart';
import 'package:admin_module/src/features/core_settings/domain/model/core_setting.dart';
import 'package:admin_module/src/features/core_settings/domain/parameters/core_settings_parameters.dart';
import 'package:admin_module/src/features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'package:admin_module/src/features/core_settings/presentation/controllers/core_settings_controller.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/admin_grpc_mock.dart';

CoreSettingsController _controller(MockAdminClient client) =>
    CoreSettingsController(
      listUsecase: ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: client),
        ),
      ),
      upsertUsecase: UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: client),
        ),
      ),
      deleteUsecase: DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: client),
        ),
      ),
    );

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  void listaResponde(List<proto.CoreSetting> settings) =>
      when(() => client.listCoreSettings(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListCoreSettingsResponse(settings: settings)),
      );

  test('converte as configurações, preservando a marca de cifrada', () async {
    listaResponde([
      proto.CoreSetting(
        key: 'openai_api_key',
        value: '****',
        encrypted: true,
        description: 'Chave da OpenAI',
      ),
      proto.CoreSetting(
        key: 'timezone',
        value: 'America/Sao_Paulo',
        encrypted: false,
        description: 'Fuso',
      ),
    ]);

    final r = await ListCoreSettingsUsecase(
      repository: ListCoreSettingsRepository(
        datasource: ListCoreSettingsDatasource(client: client),
      ),
    )(noParams);

    final lista = (r as Success<List<CoreSetting>, CoreSettingsError>).value;
    expect(lista, hasLength(2));
    expect(lista.first.encrypted, isTrue);
    expect(
      lista.first.value,
      '****',
      reason: 'o valor cifrado chega mascarado do servidor',
    );
    expect(lista.last.encrypted, isFalse);
  });

  test('upsert envia chave, valor e a marca de cifragem', () async {
    when(
      () => client.upsertCoreSetting(any()),
    ).thenAnswer((_) => respostaGrpc(proto.UpsertCoreSettingResponse()));

    await UpsertCoreSettingUsecase(
      repository: UpsertCoreSettingRepository(
        datasource: UpsertCoreSettingDatasource(client: client),
      ),
    )(
      const UpsertCoreSettingParameters(
        key: 'groq_api_key',
        value: 'gsk-nova',
        encrypted: true,
        description: 'Chave da Groq',
      ),
    );

    final enviado =
        verify(() => client.upsertCoreSetting(captureAny())).captured.single
            as proto.UpsertCoreSettingRequest;
    expect(enviado.key, 'groq_api_key');
    expect(enviado.value, 'gsk-nova');
    expect(enviado.encrypted, isTrue);
  });

  group('CoreSettingsController', () {
    blocTest<CoreSettingsController, ViewState<List<CoreSetting>>>(
      'carrega a lista: [Loading, Success]',
      build: () {
        listaResponde([
          proto.CoreSetting(key: 'k', value: 'v', description: 'd'),
        ]);
        return _controller(client);
      },
      act: (c) => c.fetchSettings(),
      expect: () => [
        isA<LoadingState<List<CoreSetting>>>(),
        isA<SuccessState<List<CoreSetting>>>().having(
          (s) => s.data,
          'settings',
          hasLength(1),
        ),
      ],
    );

    blocTest<CoreSettingsController, ViewState<List<CoreSetting>>>(
      'não superusuário: [Loading, Error] com acesso negado',
      build: () {
        when(() => client.listCoreSettings(any())).thenAnswer(
          (_) => falhaGrpc(proto.GrpcError.permissionDenied('nao superuser')),
        );
        return _controller(client);
      },
      act: (c) => c.fetchSettings(),
      expect: () => [
        isA<LoadingState<List<CoreSetting>>>(),
        isA<ErrorState<List<CoreSetting>>>().having(
          (s) => s.error,
          'erro',
          isA<CoreSettingsAcessoNegado>(),
        ),
      ],
    );

    test('salvar com sucesso recarrega a lista', () async {
      listaResponde([]);
      when(
        () => client.upsertCoreSetting(any()),
      ).thenAnswer((_) => respostaGrpc(proto.UpsertCoreSettingResponse()));
      final controller = _controller(client);

      final r = await controller.upsertSetting(
        key: 'k',
        value: 'v',
        encrypted: false,
        description: 'd',
      );

      expect(r, isA<Success>());
      verify(() => client.listCoreSettings(any())).called(1);
      await controller.close();
    });

    test('excluir com sucesso recarrega a lista', () async {
      listaResponde([]);
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => respostaGrpc(proto.DeleteCoreSettingResponse()));
      final controller = _controller(client);

      final r = await controller.deleteSetting('k');

      expect(r, isA<Success>());
      verify(() => client.listCoreSettings(any())).called(1);
      await controller.close();
    });

    test('excluir configuração inexistente devolve não encontrado', () async {
      listaResponde([]);
      when(
        () => client.deleteCoreSetting(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.notFound('sem chave')));
      final controller = _controller(client);

      final r = await controller.deleteSetting('inexistente');

      expect((r as Failure).error, isA<CoreSettingsNaoEncontrado>());
      verifyNever(() => client.listCoreSettings(any()));
      await controller.close();
    });
  });
}
