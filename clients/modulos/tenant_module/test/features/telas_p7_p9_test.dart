import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/features/conexoes/data/datasources/conexoes_datasources.dart';
import 'package:tenant_module/src/features/conexoes/data/repositories/conexoes_repositories.dart';
import 'package:tenant_module/src/features/conexoes/domain/usecases/conexoes_usecases.dart';
import 'package:tenant_module/src/features/conexoes/presentation/controllers/conexoes_controllers.dart';
import 'package:tenant_module/src/features/conexoes/presentation/pages/conexoes_page.dart';
import 'package:tenant_module/src/features/equipe/data/datasources/equipe_datasources.dart';
import 'package:tenant_module/src/features/equipe/data/repositories/equipe_repositories.dart';
import 'package:tenant_module/src/features/equipe/domain/usecases/equipe_usecases.dart';
import 'package:tenant_module/src/features/ignorados/data/datasources/ignorados_datasources.dart';
import 'package:tenant_module/src/features/ignorados/data/repositories/ignorados_repositories.dart';
import 'package:tenant_module/src/features/ignorados/domain/usecases/ignorados_usecases.dart';
import 'package:tenant_module/src/features/ignorados/presentation/controllers/ignorados_controller.dart';
import 'package:tenant_module/src/features/ignorados/presentation/pages/ignorados_page.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// P7 e P9 — as telas novas: números ignorados, departamento/detalhe/sessão da
/// conexão e mensagens não entregues.
void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyNumerosIgnoradosRequest());
    registerFallbackValue(proto.CriarNumeroIgnoradoRequest());
    registerFallbackValue(proto.AtualizarNumeroIgnoradoRequest());
    registerFallbackValue(proto.NumeroIgnoradoIdRequest());
    registerFallbackValue(proto.ListMyWhatsappInstancesRequest());
    registerFallbackValue(proto.MyWhatsappInstanceIdRequest());
    registerFallbackValue(proto.GetMyWhatsappInstanceStatusRequest());
    registerFallbackValue(proto.DefinirDepartamentoDaConexaoRequest());
    registerFallbackValue(proto.DetalheDaConexaoRequest());
    registerFallbackValue(proto.ListMyDepartamentosRequest());
    registerFallbackValue(proto.ListMyAtendentesRequest());
    registerFallbackValue(proto.ListMyMensagensNaoEntreguesRequest());
    registerFallbackValue(proto.ReenviarMensagemNaoEntregueRequest());
  });

  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  Future<void> montar(WidgetTester tester, Widget pagina) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => pagina)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  final ok = proto.SimpleOkResponse(sucesso: true);

  // ------------------------------------------------------ números ignorados
  group('IgnoradosPage', () {
    void registrar(List<proto.MyNumeroIgnorado> itens) {
      when(() => client.listMyNumerosIgnorados(any())).thenAnswer(
        (_) =>
            respostaGrpc(proto.ListMyNumerosIgnoradosResponse(itens: itens)),
      );
      getIt.registerSingleton<IgnoradosController>(
        IgnoradosController(
          listar: ListarIgnoradosUsecase(
            repository: ListarIgnoradosRepository(
              datasource: ListarIgnoradosDatasource(client: client),
            ),
          ),
          criar: CriarIgnoradoUsecase(
            repository: CriarIgnoradoRepository(
              datasource: CriarIgnoradoDatasource(client: client),
            ),
          ),
          atualizar: AtualizarIgnoradoUsecase(
            repository: AtualizarIgnoradoRepository(
              datasource: AtualizarIgnoradoDatasource(client: client),
            ),
          ),
          remover: RemoverIgnoradoUsecase(
            repository: RemoverIgnoradoRepository(
              datasource: RemoverIgnoradoDatasource(client: client),
            ),
          ),
        ),
      );
    }

    proto.MyNumeroIgnorado item({bool ativo = true}) => proto.MyNumeroIgnorado(
      id: 1,
      nome: 'Contador',
      telefone: '5511999999999',
      ativo: ativo,
      criadoEm: Int64(DateTime(2026, 9, 1).millisecondsSinceEpoch),
    );

    testWidgets('lista vazia explica que tudo abre atendimento', (
      tester,
    ) async {
      registrar([]);
      await montar(tester, const IgnoradosPage());

      expect(find.text('Nenhum número ignorado'), findsOneWidget);
    });

    testWidgets('mostra o número e quem é', (tester) async {
      registrar([item()]);
      await montar(tester, const IgnoradosPage());

      expect(find.text('5511999999999'), findsOneWidget);
      expect(find.text('Contador'), findsOneWidget);
    });

    testWidgets('o interruptor desliga a regra mantendo o cadastro', (
      tester,
    ) async {
      registrar([item()]);
      when(
        () => client.atualizarNumeroIgnorado(any()),
      ).thenAnswer((_) => respostaGrpc(ok));
      await montar(tester, const IgnoradosPage());

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      final enviado =
          verify(
                () => client.atualizarNumeroIgnorado(captureAny()),
              ).captured.single
              as proto.AtualizarNumeroIgnoradoRequest;
      expect(enviado.ativo, isFalse);
      expect(enviado.nome, 'Contador');
    });

    testWidgets('acrescentar pelo diálogo manda o número digitado', (
      tester,
    ) async {
      registrar([]);
      when(() => client.criarNumeroIgnorado(any())).thenAnswer(
        (_) => respostaGrpc(proto.MyNumeroIgnoradoResponse(item: item())),
      );
      await montar(tester, const IgnoradosPage());

      await tester.tap(find.byTooltip('Ignorar um número'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '5511888887777');
      await tester.enterText(find.byType(TextField).last, 'Fornecedor');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado =
          verify(() => client.criarNumeroIgnorado(captureAny())).captured.single
              as proto.CriarNumeroIgnoradoRequest;
      expect(enviado.telefone, '5511888887777');
      expect(enviado.nome, 'Fornecedor');
    });

    testWidgets('sem número o diálogo não chama o servidor', (tester) async {
      registrar([]);
      await montar(tester, const IgnoradosPage());

      await tester.tap(find.byTooltip('Ignorar um número'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o número.'), findsOneWidget);
      verifyNever(() => client.criarNumeroIgnorado(any()));
    });

    testWidgets('editar reaproveita o cadastro e salva', (tester) async {
      registrar([item()]);
      when(
        () => client.atualizarNumeroIgnorado(any()),
      ).thenAnswer((_) => respostaGrpc(ok));
      await montar(tester, const IgnoradosPage());

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'Contabilidade');
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado =
          verify(
                () => client.atualizarNumeroIgnorado(captureAny()),
              ).captured.single
              as proto.AtualizarNumeroIgnoradoRequest;
      expect(enviado.nome, 'Contabilidade');
      expect(enviado.ativo, isTrue);
    });

    testWidgets('remover pede confirmação', (tester) async {
      registrar([item()]);
      when(
        () => client.removerNumeroIgnorado(any()),
      ).thenAnswer((_) => respostaGrpc(ok));
      await montar(tester, const IgnoradosPage());

      await tester.tap(find.byTooltip('Remover da lista'));
      await tester.pumpAndSettle();
      expect(find.textContaining('desligue em vez de remover'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();

      verify(() => client.removerNumeroIgnorado(any())).called(1);
    });
  });

  // ------------------------------------------------------------- conexões
  group('ConexoesPage (P7/P9)', () {
    void registrar({int departamentoId = 0, String departamento = ''}) {
      when(() => client.listMyWhatsappInstances(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyWhatsappInstancesResponse(
            instancias: [
              proto.MyWhatsappInstance(
                id: 1,
                name: 'atendimento',
                phoneNumber: '5588999999999',
                connectionState: 'connected',
                active: true,
                provider: 'evolution',
                createdAt: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
                departamentoId: departamentoId,
                departamentoNome: departamento,
              ),
            ],
          ),
        ),
      );
      when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetMyWhatsappInstanceStatusResponse(
            connectionState: 'connected',
          ),
        ),
      );
      getIt.registerSingleton<ConexoesController>(
        ConexoesController(
          listar: ListarConexoesUsecase(
            repository: ListarConexoesRepository(
              datasource: ListarConexoesDatasource(client: client),
            ),
          ),
          reconectar: ReconectarConexaoUsecase(
            repository: ReconectarConexaoRepository(
              datasource: ReconectarConexaoDatasource(client: client),
            ),
          ),
          remover: RemoverConexaoUsecase(
            repository: RemoverConexaoRepository(
              datasource: RemoverConexaoDatasource(client: client),
            ),
          ),
          criar: CriarConexaoUsecase(
            repository: CriarConexaoRepository(
              datasource: CriarConexaoDatasource(client: client),
            ),
          ),
          pareamento: EstadoPareamentoUsecase(
            repository: EstadoPareamentoRepository(
              datasource: EstadoPareamentoDatasource(client: client),
            ),
          ),
          respostaBot: DefinirRespostaBotUsecase(
            repository: DefinirRespostaBotRepository(
              datasource: DefinirRespostaBotDatasource(client: client),
            ),
          ),
          desconectar: DesconectarConexaoUsecase(
            repository: DesconectarConexaoRepository(
              datasource: DesconectarConexaoDatasource(client: client),
            ),
          ),
          definirDepartamento: DefinirDepartamentoDaConexaoUsecase(
            repository: DefinirDepartamentoDaConexaoRepository(
              datasource: DefinirDepartamentoDaConexaoDatasource(
                client: client,
              ),
            ),
          ),
          detalhe: DetalheDaConexaoUsecase(
            repository: DetalheDaConexaoRepository(
              datasource: DetalheDaConexaoDatasource(client: client),
            ),
          ),
        ),
      );
    }

    Future<void> abrirMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byTooltip('Mais ações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('o cartão diz para onde o número roteia', (tester) async {
      registrar(departamentoId: 4, departamento: 'Vendas');
      await montar(tester, const ConexoesPage());

      expect(find.text('Entra no fluxo de Vendas'), findsOneWidget);
    });

    testWidgets('sem departamento o cartão explica o padrão', (tester) async {
      registrar();
      await montar(tester, const ConexoesPage());

      expect(find.textContaining('primeiro fluxo ativo'), findsOneWidget);
    });

    testWidgets('escolher o departamento pela caixa', (tester) async {
      registrar();
      when(() => client.listMyDepartamentos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyDepartamentosResponse(
            departamentos: [
              proto.MyDepartamento(id: 4, nome: 'Vendas', ativo: true),
            ],
          ),
        ),
      );
      when(
        () => client.listMyAtendentes(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListMyAtendentesResponse()));
      when(
        () => client.definirDepartamentoDaConexao(any()),
      ).thenAnswer((_) => respostaGrpc(ok));
      getIt.registerSingleton<CarregarEquipeUsecase>(
        CarregarEquipeUsecase(
          repository: CarregarEquipeRepository(
            datasource: CarregarEquipeDatasource(client: client),
          ),
        ),
      );
      await montar(tester, const ConexoesPage());

      await abrirMenu(tester, 'Departamento');
      await tester.tap(find.text('Vendas'));
      await tester.pumpAndSettle();

      final enviado =
          verify(
                () => client.definirDepartamentoDaConexao(captureAny()),
              ).captured.single
              as proto.DefinirDepartamentoDaConexaoRequest;
      expect(enviado.departamentoId, 4);
      expect(find.text('Entra no fluxo de Vendas'), findsOneWidget);
    });

    testWidgets('sem departamento ativo a caixa nem abre, e explica', (
      tester,
    ) async {
      registrar();
      when(() => client.listMyDepartamentos(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyDepartamentosResponse()),
      );
      when(
        () => client.listMyAtendentes(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListMyAtendentesResponse()));
      getIt.registerSingleton<CarregarEquipeUsecase>(
        CarregarEquipeUsecase(
          repository: CarregarEquipeRepository(
            datasource: CarregarEquipeDatasource(client: client),
          ),
        ),
      );
      await montar(tester, const ConexoesPage());

      await abrirMenu(tester, 'Departamento');

      expect(find.textContaining('Crie um em Equipe'), findsOneWidget);
    });

    testWidgets('o detalhe mostra a instância no provedor', (tester) async {
      registrar();
      when(() => client.detalheDaConexao(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.DetalheDaConexaoResponse(
            conexao: proto.MyWhatsappInstance(
              id: 1,
              name: 'atendimento',
              connectionState: 'connected',
              phoneNumber: '5588999999999',
              createdAt: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
            ),
            ultimaChecagem: Int64(
              DateTime(2026, 9, 1, 10, 5).millisecondsSinceEpoch,
            ),
            instanciaNoProvedor: 'inst-181',
            atendimentosAbertos: 3,
            mensagens24h: 40,
          ),
        ),
      );
      await montar(tester, const ConexoesPage());

      await abrirMenu(tester, 'Detalhe da conexão');

      expect(find.text('inst-181'), findsOneWidget);
      expect(find.text('01/09 às 10:05'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      await tester.tap(find.byTooltip('Fechar'));
      await tester.pumpAndSettle();
      expect(find.text('inst-181'), findsNothing);
    });

    testWidgets('encerrar a sessão pede confirmação e chama o logout', (
      tester,
    ) async {
      registrar();
      when(
        () => client.desconectarMyWhatsappInstance(any()),
      ).thenAnswer((_) => respostaGrpc(ok));
      await montar(tester, const ConexoesPage());

      await abrirMenu(tester, 'Encerrar a sessão');
      expect(find.textContaining('diferente de remover'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Encerrar'));
      await tester.pumpAndSettle();

      verify(() => client.desconectarMyWhatsappInstance(any())).called(1);
    });

    testWidgets('mensagens não entregues listam e reenviam', (tester) async {
      registrar();
      when(() => client.listMyMensagensNaoEntregues(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyMensagensNaoEntreguesResponse(
            itens: [
              proto.MensagemNaoEntregue(
                id: 7,
                atendimentoId: 9,
                motivo: 'sem destino',
                trecho: 'Seu pedido saiu',
                contato: 'Maria',
                criadoEm: Int64(DateTime(2026, 9, 1).millisecondsSinceEpoch),
              ),
            ],
          ),
        ),
      );
      when(() => client.reenviarMensagemNaoEntregue(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ReenviarMensagemNaoEntregueResponse(status: 'ainda_sem_destino'),
        ),
      );
      getIt
        ..registerSingleton<ListarNaoEntreguesUsecase>(
          ListarNaoEntreguesUsecase(
            repository: ListarNaoEntreguesRepository(
              datasource: ListarNaoEntreguesDatasource(client: client),
            ),
          ),
        )
        ..registerSingleton<ReenviarNaoEntregueUsecase>(
          ReenviarNaoEntregueUsecase(
            repository: ReenviarNaoEntregueRepository(
              datasource: ReenviarNaoEntregueDatasource(client: client),
            ),
          ),
        );
      await montar(tester, const ConexoesPage());

      await tester.tap(find.byTooltip('Mensagens não entregues'));
      await tester.pumpAndSettle();
      expect(find.text('Maria'), findsOneWidget);

      await tester.tap(find.text('Reenviar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('ainda não tem conexão ativa'), findsOneWidget);
    });

    testWidgets('nada parado mostra o vazio', (tester) async {
      registrar();
      when(() => client.listMyMensagensNaoEntregues(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyMensagensNaoEntreguesResponse()),
      );
      getIt
        ..registerSingleton<ListarNaoEntreguesUsecase>(
          ListarNaoEntreguesUsecase(
            repository: ListarNaoEntreguesRepository(
              datasource: ListarNaoEntreguesDatasource(client: client),
            ),
          ),
        )
        ..registerSingleton<ReenviarNaoEntregueUsecase>(
          ReenviarNaoEntregueUsecase(
            repository: ReenviarNaoEntregueRepository(
              datasource: ReenviarNaoEntregueDatasource(client: client),
            ),
          ),
        );
      await montar(tester, const ConexoesPage());

      await tester.tap(find.byTooltip('Mensagens não entregues'));
      await tester.pumpAndSettle();

      expect(find.text('Nada parado'), findsOneWidget);
    });
  });
}
