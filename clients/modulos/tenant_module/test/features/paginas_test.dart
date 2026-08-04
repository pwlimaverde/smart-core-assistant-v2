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
import 'package:tenant_module/src/features/fluxos/data/datasources/fluxos_datasources.dart';
import 'package:tenant_module/src/features/fluxos/data/repositories/fluxos_repositories.dart';
import 'package:tenant_module/src/features/fluxos/domain/usecases/fluxos_usecases.dart';
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
    registerFallbackValue(proto.ListMyFluxosRequest());
    registerFallbackValue(proto.CreateMyAtendenteRequest());
    registerFallbackValue(proto.UpdateMyAtendenteRequest());
    registerFallbackValue(proto.MyAtendenteIdRequest());
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

    testWidgets('reconectar avisa para ler o QR', (tester) async {
      respondeCom('disconnected');
      when(() => client.reconnectMyWhatsappInstance(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reconectar'));
      await tester.pumpAndSettle();

      verify(() => client.reconnectMyWhatsappInstance(any())).called(1);
      expect(find.textContaining('Leia o QR code'), findsOneWidget);
    });

    testWidgets('falha ao reconectar mostra a mensagem do provedor', (
      tester,
    ) async {
      respondeCom('disconnected');
      when(() => client.reconnectMyWhatsappInstance(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.failedPrecondition('instância já está conectada'),
        ),
      );
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Reconectar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('já está conectada'), findsOneWidget);
    });

    testWidgets('remover pede confirmação e avisa sobre o histórico', (
      tester,
    ) async {
      respondeCom('connected');
      when(() => client.deleteMyWhatsappInstance(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remover conexão'));
      await tester.pumpAndSettle();

      expect(find.textContaining('continuam no histórico'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();

      verify(() => client.deleteMyWhatsappInstance(any())).called(1);
    });

    testWidgets('cancelar a remoção não chama o servidor', (tester) async {
      respondeCom('connected');
      registrar();

      await montar(tester, const ConexoesPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remover conexão'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => client.deleteMyWhatsappInstance(any()));
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
          criarAtendente: CriarAtendenteUsecase(
            repository: CriarAtendenteRepository(
              datasource: CriarAtendenteDatasource(client: client),
            ),
          ),
          atualizarAtendente: AtualizarAtendenteUsecase(
            repository: AtualizarAtendenteRepository(
              datasource: AtualizarAtendenteDatasource(client: client),
            ),
          ),
          desativarAtendente: DesativarAtendenteUsecase(
            repository: DesativarAtendenteRepository(
              datasource: DesativarAtendenteDatasource(client: client),
            ),
          ),
          fluxos: ListarFluxosUsecase(
            repository: ListarFluxosRepository(
              datasource: ListarFluxosDatasource(client: client),
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
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyFluxosResponse(
            fluxos: [
              proto.MyFluxo(
                id: 7,
                departamentoId: 1,
                departamentoNome: 'Suporte',
                nome: 'Padrao',
                ativo: true,
                etapas: 4,
              ),
            ],
          ),
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


    testWidgets('criar atendente exige o fluxo, que o banco torna obrigatorio', (
      tester,
    ) async {
      // `oraculo_atendente.fluxo_id` e NOT NULL: sem fluxo o INSERT falharia
      // com erro de constraint, que nao diz nada a quem cadastra.
      respondeListas(departamentos: [depto()]);
      when(() => client.createMyAtendente(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.MyAtendenteResponse(
            atendente: proto.MyAtendente(id: 9, nome: 'Ana'),
          ),
        ),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo atendente'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Ana Souza'),
        'Ana Souza',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'ex: ana@empresa.com.br'),
        'ana@empresa.com.br',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.createMyAtendente(captureAny()))
          .captured
          .single as proto.CreateMyAtendenteRequest;
      expect(enviado.nome, 'Ana Souza');
      expect(enviado.fluxoId, 7);
      // Sem departamento escolhido, vai 0 -- a coluna aceita NULL.
      expect(enviado.departamentoId, 0);
    });

    testWidgets('sem e-mail, a criacao e barrada dentro da janela', (
      tester,
    ) async {
      respondeListas(departamentos: [depto()]);
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo atendente'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Ana Souza'),
        'Ana Souza',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o e-mail do atendente.'), findsOneWidget);
      verifyNever(() => client.createMyAtendente(any()));
    });

    testWidgets('sem fluxo ativo, a janela diz o que fazer antes', (
      tester,
    ) async {
      respondeListas(departamentos: [depto()]);
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyFluxosResponse()),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Novo atendente'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhum fluxo ativo'), findsOneWidget);
    });

    testWidgets('editar atendente nao deixa mexer no e-mail', (tester) async {
      // O e-mail e a chave unica da pessoa dentro do tenant.
      respondeListas(
        atendentes: [
          proto.MyAtendente(
            id: 9,
            nome: 'Ana',
            email: 'ana@x.com',
            departamentoId: 0,
            fluxoId: 7,
            ativo: true,
            disponivel: true,
            maxAtendimentosSimultaneos: 5,
          ),
        ],
      );
      when(() => client.updateMyAtendente(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      expect(
        find.widgetWithText(TextField, 'ex: ana@empresa.com.br'),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Mais'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.updateMyAtendente(captureAny()))
          .captured
          .single as proto.UpdateMyAtendenteRequest;
      expect(enviado.maxAtendimentosSimultaneos, 6);
      expect(enviado.fluxoId, 7);
    });

    testWidgets('desmarcar ativo nunca deixa a pessoa disponivel', (
      tester,
    ) async {
      // Inativo e disponivel seguiria elegivel no rodizio de atribuicao sem
      // estar trabalhando.
      respondeListas(
        atendentes: [
          proto.MyAtendente(
            id: 9,
            nome: 'Ana',
            departamentoId: 0,
            fluxoId: 7,
            ativo: true,
            disponivel: true,
            maxAtendimentosSimultaneos: 5,
          ),
        ],
      );
      when(() => client.updateMyAtendente(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Ativo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.updateMyAtendente(captureAny()))
          .captured
          .single as proto.UpdateMyAtendenteRequest;
      expect(enviado.ativo, isFalse);
      expect(enviado.disponivel, isFalse);
    });

    testWidgets('a recusa por conversa em andamento chega inteira', (
      tester,
    ) async {
      respondeListas(
        atendentes: [
          proto.MyAtendente(id: 9, nome: 'Ana', ativo: true, fluxoId: 7),
        ],
      );
      when(() => client.desativarMyAtendente(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.invalidArgument(
            'Esta pessoa esta com 3 conversa(s) em andamento.',
          ),
        ),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Atendentes'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Desativar'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
      await tester.pumpAndSettle();

      expect(
        find.text('Esta pessoa esta com 3 conversa(s) em andamento.'),
        findsOneWidget,
      );
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

    testWidgets('editar abre o formulário preenchido e salva', (tester) async {
      respondeListas(departamentos: [depto()]);
      when(() => client.updateMyDepartamento(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      // O formulário chega com o que já existe — editar não é recomeçar.
      expect(find.widgetWithText(TextField, 'Suporte'), findsOneWidget);
      expect(find.text('Ativo'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, 'Suporte'),
        'Suporte N1',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.updateMyDepartamento(captureAny()))
          .captured
          .single as proto.UpdateMyDepartamentoRequest;
      expect(enviado.nome, 'Suporte N1');
      expect(enviado.id, 1);
    });

    testWidgets('erro ao salvar fica DENTRO da janela, que não fecha', (
      tester,
    ) async {
      // Um SnackBar renderiza atrás do barrier modal: o usuário clicaria em
      // salvar e não veria nada acontecer.
      respondeListas(departamentos: [depto()]);
      when(() => client.updateMyDepartamento(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.invalidArgument('nome já usado')),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('nome já usado'), findsOneWidget);
      expect(find.text('Editar departamento'), findsOneWidget);
    });

    testWidgets('desativar pede confirmação e explica o efeito', (
      tester,
    ) async {
      respondeListas(departamentos: [depto()]);
      when(() => client.desativarMyDepartamento(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Desativar'));
      await tester.pumpAndSettle();

      // Desativar não apaga: o histórico fica, e dá para reativar.
      expect(find.textContaining('continuam no histórico'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
      await tester.pumpAndSettle();

      verify(() => client.desativarMyDepartamento(any())).called(1);
    });

    testWidgets('cancelar a desativação não chama o servidor', (tester) async {
      respondeListas(departamentos: [depto()]);
      registrar();

      await montar(tester, const EquipePage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Desativar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => client.desativarMyDepartamento(any()));
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
