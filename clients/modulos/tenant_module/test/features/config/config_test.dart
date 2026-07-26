import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/config/data/datasources/config_datasources.dart';
import 'package:tenant_module/src/features/config/data/repositories/config_repositories.dart';
import 'package:tenant_module/src/features/config/domain/errors/config_errors.dart';
import 'package:tenant_module/src/features/config/domain/model/tenant_config.dart';
import 'package:tenant_module/src/features/config/domain/parameters/config_parameters.dart';
import 'package:tenant_module/src/features/config/domain/usecases/config_usecases.dart';
import 'package:tenant_module/src/features/config/presentation/controllers/tenant_own_config_controller.dart';

import '../../support/admin_client_mock.dart';

({GetMyTenantConfigUsecase get, UpdateMyTenantConfigUsecase update}) _usecases(
  MockAdminClient client,
) => (
  get: GetMyTenantConfigUsecase(
    repository: GetMyTenantConfigRepository(
      datasource: GetMyTenantConfigDatasource(client: client),
    ),
  ),
  update: UpdateMyTenantConfigUsecase(
    repository: UpdateMyTenantConfigRepository(
      datasource: UpdateMyTenantConfigDatasource(client: client),
    ),
  ),
);

TenantOwnConfigController _controller(MockAdminClient client) {
  final u = _usecases(client);
  return TenantOwnConfigController(getUsecase: u.get, updateUsecase: u.update);
}

const _config = TenantConfig(
  dadosEmpresa: 'Empresa X',
  personaBot: 'atendente cordial',
  botAgentName: 'Ana',
  msgFallback: 'nao entendi',
  msgSemInfo: 'sem informacao',
  msgTransferencia: 'transferindo',
  llmClass: 'groq',
  model: 'llama-3.3',
  llmTemperature: '0.2',
  transcriptionProvider: 'groq',
  transcriptionModel: 'whisper',
  visionProvider: 'google',
  visionModel: 'gemini',
  embeddingsClass: 'openai',
  embeddingsModel: 'text-embedding-3',
  chunkSize: 800,
  chunkOverlap: 100,
  similarityThreshold: '0.75',
  vectorDistanceThreshold: '0.3',
  apiKeys: {'groq': 'gsk-secreta'},
);

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoTenant);
  setUp(() => client = MockAdminClient());

  group('GetMyTenantConfig', () {
    test('converte a resposta, inclusive o mapa de chaves de API', () async {
      when(() => client.getMyTenantConfig(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetTenantConfigResponse(
            dadosEmpresa: 'Empresa X',
            personaBot: 'atendente cordial',
            botAgentName: 'Ana',
            llmClass: 'groq',
            model: 'llama-3.3',
            llmTemperature: '0.2',
            chunkSize: 800,
            chunkOverlap: 100,
            similarityThreshold: '0.75',
            vectorDistanceThreshold: '0.3',
            apiKeys: [
              proto.ApiKeyEntry(key: 'groq', value: '****'),
              proto.ApiKeyEntry(key: 'openai', value: '****'),
            ],
          ),
        ),
      );

      final r = await _usecases(client).get(noParams);

      final config = (r as Success<TenantConfig, TenantConfigError>).value;
      expect(config.dadosEmpresa, 'Empresa X');
      expect(config.botAgentName, 'Ana');
      expect(config.chunkSize, 800);
      expect(config.apiKeys, {'groq': '****', 'openai': '****'});
    });

    test('resposta sem chaves de API vira mapa vazio', () async {
      when(
        () => client.getMyTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.GetTenantConfigResponse()));

      final r = await _usecases(client).get(noParams);

      expect((r as Success).value.apiKeys, isEmpty);
    });

    test('sem permissão vira acesso negado', () async {
      when(() => client.getMyTenantConfig(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      final erro = ((await _usecases(client).get(noParams)) as Failure).error;

      expect(erro, isA<ConfigAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
    });

    test('servidor fora do ar é falha de rede', () async {
      when(
        () => client.getMyTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('offline')));

      final erro = ((await _usecases(client).get(noParams)) as Failure).error;

      expect(erro, isA<ConfigIndisponivel>());
      expect(erro, isA<NetworkFailure>());
    });
  });

  group('UpdateMyTenantConfig', () {
    test('envia todos os campos e as chaves de API', () async {
      when(
        () => client.updateMyTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantConfigResponse()));

      final r = await _usecases(
        client,
      ).update(const UpdateMyTenantConfigParameters(config: _config));

      final enviado =
          verify(
                () => client.updateMyTenantConfig(captureAny()),
              ).captured.single
              as proto.UpdateMyTenantConfigRequest;
      expect(enviado.dadosEmpresa, 'Empresa X');
      expect(enviado.chunkSize, 800);
      expect(enviado.similarityThreshold, '0.75');
      expect(enviado.apiKeys.single.key, 'groq');
      expect(r, isA<Success<Unit, TenantConfigError>>());
    });

    test('valor fora da faixa vira dados inválidos', () async {
      when(() => client.updateMyTenantConfig(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.invalidArgument('temperature > 1')),
      );

      final r = await _usecases(
        client,
      ).update(const UpdateMyTenantConfigParameters(config: _config));

      final erro = (r as Failure).error;
      expect(erro, isA<ConfigDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
    });

    test('a chave de API nunca aparece na mensagem de erro', () async {
      when(() => client.updateMyTenantConfig(any())).thenAnswer(
        (_) =>
            falhaGrpc(proto.GrpcError.internal('falha ao cifrar gsk-secreta')),
      );

      final r = await _usecases(
        client,
      ).update(const UpdateMyTenantConfigParameters(config: _config));

      final erro = (r as Failure).error as TenantConfigError;
      expect(erro.message, isNot(contains('gsk-secreta')));
      expect(erro, isA<ConfigInesperado>());
    });
  });

  group('TenantOwnConfigController', () {
    blocTest<TenantOwnConfigController, ViewState<TenantConfig>>(
      'carrega a configuração: [Loading, Success]',
      build: () {
        when(() => client.getMyTenantConfig(any())).thenAnswer(
          (_) =>
              respostaGrpc(proto.GetTenantConfigResponse(botAgentName: 'Ana')),
        );
        return _controller(client);
      },
      act: (c) => c.fetchConfig(),
      expect: () => [
        isA<LoadingState<TenantConfig>>(),
        isA<SuccessState<TenantConfig>>().having(
          (s) => s.data.botAgentName,
          'botAgentName',
          'Ana',
        ),
      ],
    );

    blocTest<TenantOwnConfigController, ViewState<TenantConfig>>(
      'falha: [Loading, Error]',
      build: () {
        when(
          () => client.getMyTenantConfig(any()),
        ).thenAnswer((_) => falhaGrpc(proto.GrpcError.permissionDenied('x')));
        return _controller(client);
      },
      act: (c) => c.fetchConfig(),
      expect: () => [
        isA<LoadingState<TenantConfig>>(),
        isA<ErrorState<TenantConfig>>().having(
          (s) => s.error,
          'erro',
          isA<ConfigAcessoNegado>(),
        ),
      ],
    );

    test('salvar com sucesso recarrega a configuração', () async {
      when(
        () => client.getMyTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.GetTenantConfigResponse()));
      when(
        () => client.updateMyTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantConfigResponse()));
      final controller = _controller(client);

      final r = await controller.updateConfig(_config);

      expect(r, isA<Success>());
      verify(() => client.getMyTenantConfig(any())).called(1);
      await controller.close();
    });

    test('salvar com falha não recarrega', () async {
      when(
        () => client.getMyTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.GetTenantConfigResponse()));
      when(
        () => client.updateMyTenantConfig(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.invalidArgument('x')));
      final controller = _controller(client);

      final r = await controller.updateConfig(_config);

      expect((r as Failure).error, isA<ConfigDadosInvalidos>());
      verifyNever(() => client.getMyTenantConfig(any()));
      await controller.close();
    });
  });
}
