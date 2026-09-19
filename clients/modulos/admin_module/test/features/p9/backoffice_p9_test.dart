import 'dart:convert';

import 'package:admin_module/src/features/core_settings/data/datasources/core_settings_datasources.dart';
import 'package:admin_module/src/features/core_settings/data/repositories/core_settings_repositories.dart';
import 'package:admin_module/src/features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'package:admin_module/src/features/core_settings/presentation/controllers/core_settings_controller.dart';
import 'package:admin_module/src/features/evolution/data/datasources/evolution_datasources.dart';
import 'package:admin_module/src/features/evolution/data/repositories/evolution_repositories.dart';
import 'package:admin_module/src/features/evolution/domain/errors/evolution_errors.dart';
import 'package:admin_module/src/features/evolution/domain/model/evolution_connection_result.dart';
import 'package:admin_module/src/features/evolution/domain/parameters/evolution_parameters.dart';
import 'package:admin_module/src/features/evolution/domain/usecases/evolution_usecases.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/admin_grpc_mock.dart';

/// P9 — backoffice: exportar/importar configurações e testar o provedor de IA.
void main() {
  late MockAdminClient client;

  setUpAll(() {
    registrarFallbacksDoAdmin();
    registerFallbackValue(proto.TestarProvedorIaRequest());
  });
  setUp(() => client = MockAdminClient());

  CoreSettingsController settings() => CoreSettingsController(
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

  void listaResponde() =>
      when(() => client.listCoreSettings(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListCoreSettingsResponse(
            settings: [
              proto.CoreSetting(
                key: 'openai_api_key',
                value: 'sk-segredo',
                encrypted: true,
              ),
              proto.CoreSetting(key: 'timezone', value: 'America/Sao_Paulo'),
            ],
          ),
        ),
      );

  group('exportar', () {
    test('o valor cifrado não sai, só a chave', () async {
      // Exportar o segredo em claro para a área de transferência seria vazá-lo;
      // e o valor cifrado não serve em outro ambiente, que tem outra chave.
      listaResponde();
      final c = settings();
      await c.fetchSettings();

      final json = jsonDecode(c.exportarJson()) as List;

      final cifrada = json.firstWhere((e) => e['key'] == 'openai_api_key');
      expect(cifrada['value'], '');
      expect(cifrada['encrypted'], isTrue);
      final comum = json.firstWhere((e) => e['key'] == 'timezone');
      expect(comum['value'], 'America/Sao_Paulo');
      await c.close();
    });
  });

  group('importar', () {
    test('cifrada sem valor é pulada, não gravada vazia', () async {
      // Gravar vazio apagaria o segredo que o ambiente de destino já tem.
      listaResponde();
      when(() => client.upsertCoreSetting(any())).thenAnswer(
        (_) => respostaGrpc(proto.UpsertCoreSettingResponse(success: true)),
      );
      final c = settings();

      final r = await c.importarJson(
        jsonEncode([
          {'key': 'openai_api_key', 'value': '', 'encrypted': true},
          {'key': 'timezone', 'value': 'UTC', 'encrypted': false},
        ]),
      );

      expect(r.erro, isNull);
      expect(r.gravadas, 1);
      expect(r.puladas, 1);
      final enviado =
          verify(
                () => client.upsertCoreSetting(captureAny()),
              ).captured.single
              as proto.UpsertCoreSettingRequest;
      expect(enviado.key, 'timezone');
      await c.close();
    });

    test('JSON quebrado vira mensagem, e nada é gravado', () async {
      final c = settings();

      final r = await c.importarJson('{isto não é json');

      expect(r.erro, isNotNull);
      verifyNever(() => client.upsertCoreSetting(any()));
      await c.close();
    });

    test('objeto no lugar de lista é recusado', () async {
      final c = settings();

      final r = await c.importarJson('{"key": "x"}');

      expect(r.erro, contains('lista'));
      await c.close();
    });
  });

  group('testar provedor de IA', () {
    TestarProvedorIaUsecase usecase() => TestarProvedorIaUsecase(
      repository: TestarProvedorIaRepository(
        datasource: TestarProvedorIaDatasource(client: client),
      ),
    );

    test('provedor fora não é erro do teste: vem ok=false com o motivo', () async {
      when(() => client.testarProvedorIa(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.TestarProvedorIaResponse(
            ok: false,
            latenciaMs: 812,
            erro: 'chave inválida',
          ),
        ),
      );

      final r = await usecase()(
        const TestarProvedorIaParameters(tenantId: 't-1'),
      );

      final teste = (r as Success<TesteProvedorIa, EvolutionError>).value;
      expect(teste.ok, isFalse);
      expect(teste.erro, 'chave inválida');
    });

    test('provedor respondendo traz latência e dimensões', () async {
      when(() => client.testarProvedorIa(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.TestarProvedorIaResponse(
            ok: true,
            latenciaMs: 120,
            dimensoes: 1536,
          ),
        ),
      );

      final r = await usecase()(
        const TestarProvedorIaParameters(tenantId: 't-1'),
      );

      final teste = (r as Success<TesteProvedorIa, EvolutionError>).value;
      expect(teste.dimensoes, 1536);
      expect(teste.latenciaMs, 120);
    });
  });
}
