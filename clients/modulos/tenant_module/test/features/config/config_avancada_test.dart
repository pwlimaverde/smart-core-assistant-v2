import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/config/data/datasources/config_datasources.dart';
import 'package:tenant_module/src/features/config/data/repositories/config_repositories.dart';
import 'package:tenant_module/src/features/config/domain/errors/config_errors.dart';
import 'package:tenant_module/src/features/config/domain/model/tenant_config.dart';
import 'package:tenant_module/src/features/config/domain/usecases/config_usecases.dart';
import 'package:tenant_module/src/features/config/presentation/controllers/tenant_own_config_controller.dart';
import 'package:tenant_module/src/features/config/presentation/widgets/config_avancada_form.dart';

import '../../support/admin_client_mock.dart';

TenantOwnConfigController _controller(
  MockAdminClient client, {
  bool comAvancada = true,
}) => TenantOwnConfigController(
  getUsecase: GetMyTenantConfigUsecase(
    repository: GetMyTenantConfigRepository(
      datasource: GetMyTenantConfigDatasource(client: client),
    ),
  ),
  updateUsecase: UpdateMyTenantConfigUsecase(
    repository: UpdateMyTenantConfigRepository(
      datasource: UpdateMyTenantConfigDatasource(client: client),
    ),
  ),
  updateAvancadaUsecase: comAvancada
      ? UpdateConfigAvancadaUsecase(
          repository: UpdateConfigAvancadaRepository(
            datasource: UpdateConfigAvancadaDatasource(client: client),
          ),
        )
      : null,
);

/// Configuração avançada: o que o banco guardava e nenhuma tela editava.
void main() {
  late MockAdminClient client;

  setUpAll(() {
    registrarFallbacksDoTenant();
    registerFallbackValue(proto.UpdateMyConfigAvancadaRequest());
  });
  setUp(() => client = MockAdminClient());

  test('a leitura traz prompts, marca e o que herda do global', () async {
    when(() => client.getMyTenantConfig(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetTenantConfigResponse(
          entityTypesJson: '{"cidade":"onde mora"}',
          prompts: [proto.PromptDoTenant(chave: 'PROMPT_X', texto: 'y')],
          brandName: 'Ecoprint',
          primaryColor: '#315c28',
          timezone: 'America/Fortaleza',
          analisePreviaHabilitada: true,
        ),
      ),
    );

    final c = _controller(client);
    await c.fetchConfig();
    final a = (c.state as dynamic).data.avancada as ConfigAvancada;

    expect(a.prompts, {'PROMPT_X': 'y'});
    expect(a.marca, 'Ecoprint');
    expect(a.analisePrevia, isTrue);
    // Não configurado = herda: `null`, e não `false`.
    expect(a.transcricao, isNull);
    expect(a.minutosInatividade, isNull);
  });

  test('gravar manda os campos e esvazia os prompts retirados', () async {
    when(
      () => client.updateMyConfigAvancada(any()),
    ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
    when(
      () => client.getMyTenantConfig(any()),
    ).thenAnswer((_) => respostaGrpc(proto.GetTenantConfigResponse()));

    final r = await _controller(client).updateAvancada(
      const ConfigAvancada(
        prompts: {'PROMPT_A': 'novo'},
        marca: 'Eco',
        corPrimaria: '#000000',
        analisePrevia: false,
        minutosInatividade: 30,
      ),
      promptsRemovidos: {'PROMPT_B'},
    );

    expect(r, isA<Success<Unit, TenantConfigError>>());
    final req =
        verify(
              () => client.updateMyConfigAvancada(captureAny()),
            ).captured.single
            as proto.UpdateMyConfigAvancadaRequest;
    expect(
      {for (final p in req.prompts) p.chave: p.texto},
      {'PROMPT_A': 'novo', 'PROMPT_B': ''},
    );
    expect(req.brandName, 'Eco');
    expect(req.primaryColor, '#000000');
    // Cor vazia não vai: "sem valor" aqui é "não mexer".
    expect(req.hasSecondaryColor(), isFalse);
    expect(req.analisePreviaHabilitada, isFalse);
    expect(req.hasTranscriptionEnabled(), isFalse);
    expect(req.minutosInatividadeEncerra, 30);
    expect(req.entityTypesJson, '{}');
  });

  test('sem o caso de uso, a seção avançada não é oferecida', () async {
    final c = _controller(client, comAvancada: false);
    expect(c.podeEditarAvancada, isFalse);
    expect(
      await c.updateAvancada(const ConfigAvancada()),
      isA<Failure<Unit, TenantConfigError>>(),
    );
  });

  group('formulário', () {
    Future<List<(ConfigAvancada, Set<String>)>> montar(
      WidgetTester tester,
      ConfigAvancada inicial,
    ) async {
      final salvos = <(ConfigAvancada, Set<String>)>[];
      tester.view.physicalSize = const Size(1200, 3000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConfigAvancadaForm(
                avancada: inicial,
                aoSalvar: (a, removidos) async {
                  salvos.add((a, removidos));
                  return null;
                },
              ),
            ),
          ),
        ),
      );
      return salvos;
    }

    Future<void> salvar(WidgetTester tester) async {
      await tester.tap(find.text('Salvar configuração avançada'));
      await tester.pumpAndSettle();
    }

    testWidgets('JSON inválido nos tipos de entidade não é gravado', (
      tester,
    ) async {
      final salvos = await montar(tester, const ConfigAvancada());
      await tester.enterText(
        find.byKey(const Key('tipos-de-entidade')),
        '{quebrado',
      );
      await salvar(tester);

      expect(salvos, isEmpty);
      expect(find.textContaining('JSON não é válido'), findsOneWidget);
    });

    testWidgets('cor fora do formato #RRGGBB não é gravada', (tester) async {
      final salvos = await montar(tester, const ConfigAvancada());
      await tester.enterText(
        find.widgetWithText(TextField, 'Cor primária'),
        'verde',
      );
      await salvar(tester);

      expect(salvos, isEmpty);
      expect(find.textContaining('#RRGGBB'), findsOneWidget);
    });

    testWidgets('adicionar, remover e gravar prompts', (tester) async {
      final salvos = await montar(
        tester,
        const ConfigAvancada(prompts: {'PROMPT_INTENT_FOOTER': 'rodapé'}),
      );

      // Remove o que havia: vai como retirado.
      await tester.tap(find.byTooltip('Voltar ao prompt padrão'));
      await tester.pumpAndSettle();

      // Acrescenta um novo pela lista dos conhecidos.
      await tester.tap(find.text('Personalizar prompt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regras de resposta'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Regras de resposta'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'seja breve');

      await tester.tap(find.byType(Switch).first);
      await salvar(tester);

      expect(salvos, hasLength(1));
      final (a, removidos) = salvos.single;
      expect(a.prompts, {'PROMPT_REGRAS_RESPOSTA': 'seja breve'});
      expect(removidos, {'PROMPT_INTENT_FOOTER'});
      expect(a.analisePrevia, isTrue);
      expect(find.text('Configuração avançada salva.'), findsOneWidget);
    });

    testWidgets('quem só lê não vê o botão de salvar', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ConfigAvancadaForm(
                avancada: const ConfigAvancada(tiposDeEntidadeJson: '["cpf"]'),
                podeSalvar: false,
                aoSalvar: (_, _) async => null,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Salvar configuração avançada'), findsNothing);
      expect(find.textContaining('"cpf"'), findsOneWidget);
    });
  });
}
