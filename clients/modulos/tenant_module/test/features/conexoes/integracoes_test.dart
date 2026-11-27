import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/conexoes/data/datasources/conexoes_datasources.dart';
import 'package:tenant_module/src/features/conexoes/data/repositories/conexoes_repositories.dart';
import 'package:tenant_module/src/features/conexoes/domain/errors/conexoes_errors.dart';
import 'package:tenant_module/src/features/conexoes/domain/model/provedor_canal.dart';
import 'package:tenant_module/src/features/conexoes/domain/parameters/conexoes_parameters.dart';
import 'package:tenant_module/src/features/conexoes/domain/usecases/conexoes_usecases.dart';
import 'package:tenant_module/src/features/conexoes/presentation/controllers/integracoes_controller.dart';
import 'package:tenant_module/src/features/conexoes/presentation/pages/integracoes_page.dart';
import 'package:tenant_module/src/features/conexoes/presentation/widgets/formulario_do_provedor_dialog.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// Descritores como o servidor os devolve: a tela não conhece nenhum deles
/// pelo nome, só pelo modo e pelos campos.
proto.ListMyChannelProvidersResponse _catalogo() =>
    proto.ListMyChannelProvidersResponse(
      provedores: [
        proto.ProvedorDeCanal(
          id: 'evolution',
          tipoCanal: 'whatsapp',
          nome: 'WhatsApp (QR code)',
          descricao: 'Lê o QR no celular.',
          modoConexao: 'qr_pairing',
          estagio: 'estavel',
          habilitado: true,
          capacidades: ['qr_pairing', 'envio_texto'],
        ),
        proto.ProvedorDeCanal(
          id: 'meta_cloud',
          tipoCanal: 'whatsapp',
          nome: 'WhatsApp Business (API oficial)',
          descricao: 'Id do número e token.',
          modoConexao: 'token',
          estagio: 'experimental',
          habilitado: true,
          campos: [
            proto.CampoConfiguracaoCanal(
              chave: 'phone_number_id',
              rotulo: 'ID do número',
              tipo: 'texto',
              obrigatorio: true,
            ),
            proto.CampoConfiguracaoCanal(
              chave: 'access_token',
              rotulo: 'Token de acesso',
              tipo: 'segredo',
              obrigatorio: true,
              ajuda: 'Token permanente.',
            ),
          ],
          capacidades: ['token_connect', 'envio_texto'],
        ),
        proto.ProvedorDeCanal(
          id: 'webchat',
          tipoCanal: 'webchat',
          nome: 'Chat do site',
          descricao: 'Widget para o site.',
          modoConexao: 'copy_snippet',
          estagio: 'planejado',
          habilitado: false,
          motivoIndisponivel: 'Em planejamento.',
        ),
      ],
    );

void main() {
  late _MockAdminClient client;

  setUpAll(() {
    registerFallbackValue(proto.ListMyChannelProvidersRequest());
    registerFallbackValue(proto.ConnectMyChannelRequest());
  });

  setUp(() => client = _MockAdminClient());

  IntegracoesController controlador() => IntegracoesController(
    listar: ListarProvedoresUsecase(
      repository: ListarProvedoresRepository(
        datasource: ListarProvedoresDatasource(client: client),
      ),
    ),
    conectar: ConectarCanalUsecase(
      repository: ConectarCanalRepository(
        datasource: ConectarCanalDatasource(client: client),
      ),
    ),
  );

  test('catálogo traduz modo, campos e capacidades do descritor', () async {
    when(
      () => client.listMyChannelProviders(any()),
    ).thenAnswer((_) => respostaGrpc(_catalogo()));

    final res = await ListarProvedoresUsecase(
      repository: ListarProvedoresRepository(
        datasource: ListarProvedoresDatasource(client: client),
      ),
    )(noParams);
    final itens = (res as Success<List<ProvedorCanal>, ConexoesError>).value;

    expect(itens.map((p) => p.modo), [
      ModoConexao.qrPairing,
      ModoConexao.token,
      ModoConexao.copySnippet,
    ]);
    final meta = itens[1];
    expect(meta.campos.map((c) => c.tipo), [
      TipoCampoCanal.texto,
      TipoCampoCanal.segredo,
    ]);
    expect(meta.capacidades, contains('token_connect'));
    expect(meta.podeConectar, isTrue);
    // Planejado nunca abre fluxo; modo que o app não conduz também não.
    expect(itens[2].podeConectar, isFalse);
    expect(itens[2].motivoParaNaoConectar, 'Em planejamento.');
  });

  test('modo desconhecido não vira fluxo de conexão', () {
    expect(ModoConexao.doServidor('algo_novo'), ModoConexao.desconhecido);
    expect(ModoConexao.desconhecido.suportadoNoApp, isFalse);
    expect(ModoConexao.oauth.suportadoNoApp, isFalse);
  });

  test('conectar envia os campos como pares, sem map', () async {
    when(() => client.connectMyChannel(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ConnectMyChannelResponse(
          id: 9,
          instanceName: 'atendimento',
          provider: 'meta_cloud',
          phoneNumber: '5588981061874',
          connectionState: 'connected',
        ),
      ),
    );

    final res = await controlador().conectar(
      const ConectarCanalParameters(
        provedor: 'meta_cloud',
        nome: 'atendimento',
        valores: {'phone_number_id': '555', 'access_token': 'tok'},
      ),
    );
    expect((res as Success<CanalConectado, ConexoesError>).value.id, 9);

    final enviado =
        verify(() => client.connectMyChannel(captureAny())).captured.single
            as proto.ConnectMyChannelRequest;
    expect(enviado.provider, 'meta_cloud');
    expect(enviado.instanceName, 'atendimento');
    expect(
      {for (final c in enviado.campos) c.chave: c.valor},
      {'phone_number_id': '555', 'access_token': 'tok'},
    );
  });

  Future<void> abrir(WidgetTester tester, Widget filho) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: filho),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'formulário sai do descritor: um campo por item, segredo oculto',
    (tester) async {
      final meta = provedorDoProto(_catalogo().provedores[1]);
      await abrir(
        tester,
        FormularioDoProvedorDialog(controller: controlador(), provedor: meta),
      );

      expect(find.byKey(const ValueKey('campo-nome')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('campo-phone_number_id')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('campo-access_token')), findsOneWidget);
      expect(find.text('Token permanente.'), findsOneWidget);

      final segredo = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('campo-access_token')),
          matching: find.byType(TextField),
        ),
      );
      expect(segredo.obscureText, isTrue);
      final texto = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const ValueKey('campo-phone_number_id')),
          matching: find.byType(TextField),
        ),
      );
      expect(texto.obscureText, isFalse);
    },
  );

  testWidgets('obrigatório vazio é apontado sem chamar o servidor', (
    tester,
  ) async {
    final meta = provedorDoProto(_catalogo().provedores[1]);
    await abrir(
      tester,
      FormularioDoProvedorDialog(controller: controlador(), provedor: meta),
    );

    await tester.enterText(
      find.descendant(
        of: find.byKey(const ValueKey('campo-nome')),
        matching: find.byType(TextField),
      ),
      'atendimento',
    );
    await tester.tap(find.text('Conectar'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('erro-formulario')), findsOneWidget);
    expect(find.textContaining('ID do número'), findsWidgets);
    verifyNever(() => client.connectMyChannel(any()));
  });

  testWidgets('cartão desabilita o botão do provedor indisponível', (
    tester,
  ) async {
    final catalogo = _catalogo().provedores.map(provedorDoProto).toList();
    await abrir(
      tester,
      Column(
        children: [
          for (final p in catalogo)
            CartaoDoProvedor(provedor: p, onConectar: () {}),
        ],
      ),
    );

    FilledButton botao(String id) =>
        tester.widget<FilledButton>(find.byKey(ValueKey('conectar-$id')));
    expect(botao('evolution').onPressed, isNotNull);
    expect(botao('meta_cloud').onPressed, isNotNull);
    expect(botao('webchat').onPressed, isNull);
    expect(find.text('Conectar com QR code'), findsOneWidget);
    expect(find.text('Conectar com credenciais'), findsOneWidget);
    expect(find.text('Em planejamento.'), findsOneWidget);
  });
}
