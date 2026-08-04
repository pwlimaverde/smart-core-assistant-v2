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
import 'package:tenant_module/src/features/equipe/presentation/controllers/equipe_controllers.dart';
import 'package:tenant_module/src/features/equipe/presentation/pages/equipe_page.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyWhatsappInstancesRequest());
    registerFallbackValue(proto.MyWhatsappInstanceIdRequest());
    registerFallbackValue(proto.ListMyDepartamentosRequest());
    registerFallbackValue(proto.ListMyAtendentesRequest());
    registerFallbackValue(proto.CreateMyDepartamentoRequest());
    registerFallbackValue(proto.UpdateMyDepartamentoRequest());
    registerFallbackValue(proto.MyDepartamentoIdRequest());
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
    await tester.pump();
  }

  group('ConexoesPage', () {
    void registrar() {
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
        ),
      );
    }

    void respondeCom(String estado) {
      when(() => client.listMyWhatsappInstances(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyWhatsappInstancesResponse(
            instancias: [
              proto.MyWhatsappInstance(
                id: 1,
                name: 'atendimento',
                phoneNumber: '5588999999999',
                connectionState: estado,
                active: true,
                provider: 'evolution',
                createdAt: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
              ),
            ],
          ),
        ),
      );
    }

    testWidgets('lista as conexões com a situação', (tester) async {
      respondeCom('connected');
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      expect(find.text('atendimento'), findsOneWidget);
      expect(find.text('Conectada'), findsOneWidget);
    });

    testWidgets('conexão conectada NÃO oferece reconectar', (tester) async {
      // Oferecer no estado bom convidaria a derrubar o que funciona:
      // reconectar reinicia o cliente no provedor.
      respondeCom('connected');
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      expect(find.byTooltip('Reconectar'), findsNothing);
      expect(find.byTooltip('Remover conexão'), findsOneWidget);
    });

    testWidgets('conexão caída oferece reconectar', (tester) async {
      respondeCom('disconnected');
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      expect(find.text('Desconectada'), findsOneWidget);
      expect(find.byTooltip('Reconectar'), findsOneWidget);
    });

    testWidgets('sem conexões, explica o que fazer', (tester) async {
      when(() => client.listMyWhatsappInstances(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyWhatsappInstancesResponse()),
      );
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma conexão'), findsOneWidget);
    });

    testWidgets('erro do servidor vira tela de erro com retentar', (
      tester,
    ) async {
      when(() => client.listMyWhatsappInstances(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
      );
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });
  });

  group('EquipePage', () {
    void registrar() {
      getIt.registerSingleton<EquipeController>(
        EquipeController(
          carregar: CarregarEquipeUsecase(
            repository: CarregarEquipeRepository(
              datasource: CarregarEquipeDatasource(client: client),
            ),
          ),
          criar: CriarDepartamentoUsecase(
            repository: CriarDepartamentoRepository(
              datasource: CriarDepartamentoDatasource(client: client),
            ),
          ),
          atualizar: AtualizarDepartamentoUsecase(
            repository: AtualizarDepartamentoRepository(
              datasource: AtualizarDepartamentoDatasource(client: client),
            ),
          ),
          desativar: DesativarDepartamentoUsecase(
            repository: DesativarDepartamentoRepository(
              datasource: DesativarDepartamentoDatasource(client: client),
            ),
          ),
        ),
      );
    }

    void respondeListas({
      List<proto.MyDepartamento> departamentos = const [],
      List<proto.MyAtendente> atendentes = const [],
    }) {
      when(() => client.listMyDepartamentos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyDepartamentosResponse(departamentos: departamentos),
        ),
      );
      when(() => client.listMyAtendentes(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyAtendentesResponse(atendentes: atendentes),
        ),
      );
    }

    proto.MyDepartamento depto({bool ativo = true}) => proto.MyDepartamento(
          id: 1,
          nome: 'Suporte',
          slug: 'suporte',
          descricao: 'Dúvidas de pedidos',
          ativo: ativo,
          criadoEm: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
        );

    testWidgets('mostra os departamentos', (tester) async {
      respondeListas(departamentos: [depto()]);
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      expect(find.text('Suporte'), findsOneWidget);
      expect(find.text('Dúvidas de pedidos'), findsOneWidget);
    });

    testWidgets('departamento inativo é marcado e não oferece desativar', (
      tester,
    ) async {
      respondeListas(departamentos: [depto(ativo: false)]);
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      expect(find.text('Inativo'), findsOneWidget);
      expect(find.byTooltip('Desativar'), findsNothing);
      expect(find.byTooltip('Editar'), findsOneWidget);
    });

    testWidgets('sem departamento, diz por que isso trava a fila', (
      tester,
    ) async {
      respondeListas();
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      expect(find.text('Nenhum departamento'), findsOneWidget);
      expect(find.textContaining('não tem para onde mandar'), findsOneWidget);
    });

    testWidgets('aba de atendentes mostra o departamento de cada um', (
      tester,
    ) async {
      respondeListas(
        departamentos: [depto()],
        atendentes: [
          proto.MyAtendente(
            id: 9,
            nome: 'Ana',
            email: 'ana@x.com',
            cargo: 'Atendente',
            departamentoId: 1,
            ativo: true,
            disponivel: true,
            maxAtendimentosSimultaneos: 5,
          ),
        ],
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();

      expect(find.text('Ana'), findsOneWidget);
      expect(find.textContaining('Suporte'), findsWidgets);
    });

    testWidgets('atendente ativo e indisponível é marcado como tal', (
      tester,
    ) async {
      // Férias: cadastro ativo, não aceitando conversa. Confundir com inativo
      // esconderia por que a fila parou.
      respondeListas(
        atendentes: [
          proto.MyAtendente(
            id: 9,
            nome: 'Bruno',
            ativo: true,
            disponivel: false,
            departamentoId: 0,
          ),
        ],
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();

      expect(find.text('Indisponível'), findsOneWidget);
      expect(find.textContaining('sem departamento'), findsOneWidget);
    });

    testWidgets('o diálogo de novo departamento valida o nome', (tester) async {
      respondeListas();
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo departamento'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      // O erro fica DENTRO da janela: um SnackBar renderiza atrás do barrier.
      expect(find.text('Informe o nome do departamento.'), findsOneWidget);
      expect(find.text('Novo departamento'), findsWidgets);
    });
  });
}
