import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:login_module/login_module.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/equipe/data/datasources/equipe_datasources.dart';
import 'package:tenant_module/src/features/equipe/data/repositories/equipe_repositories.dart';
import 'package:tenant_module/src/features/equipe/domain/usecases/equipe_usecases.dart';
import 'package:tenant_module/src/features/fluxos/data/datasources/fluxos_datasources.dart';
import 'package:tenant_module/src/features/fluxos/data/repositories/fluxos_repositories.dart';
import 'package:tenant_module/src/features/fluxos/domain/errors/fluxos_errors.dart';
import 'package:tenant_module/src/features/fluxos/domain/model/fluxo.dart';
import 'package:tenant_module/src/features/fluxos/domain/parameters/fluxos_parameters.dart';
import 'package:tenant_module/src/features/fluxos/domain/usecases/fluxos_usecases.dart';
import 'package:tenant_module/src/features/fluxos/presentation/controllers/fluxos_controllers.dart';
import 'package:tenant_module/src/features/fluxos/presentation/pages/etapas_fluxo_page.dart';
import 'package:tenant_module/src/features/fluxos/presentation/pages/fluxos_page.dart';
import 'package:tenant_module/src/features/fluxos/presentation/widgets/dialogo_etapa.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

/// `find.byTooltip` casa com o `Tooltip` que o `IconButton` constrói por
/// dentro, não com o botão — é o botão que se quer inspecionar.
List<IconButton> _botoesDeTooltip(WidgetTester tester, String tooltip) => tester
    .widgetList<IconButton>(
      find.ancestor(
        of: find.byTooltip(tooltip),
        matching: find.byType(IconButton),
      ),
    )
    .toList();

VoidCallback? _botaoDeTooltip(WidgetTester tester, String tooltip) =>
    _botoesDeTooltip(tester, tooltip).single.onPressed;

class _MockAuthService extends Mock implements AuthService {}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyFluxosRequest());
    registerFallbackValue(proto.CreateMyFluxoRequest());
    registerFallbackValue(proto.UpdateMyFluxoRequest());
    registerFallbackValue(proto.MyFluxoIdRequest());
    registerFallbackValue(proto.CreateMyEtapaFluxoRequest());
    registerFallbackValue(proto.UpdateMyEtapaFluxoRequest());
    registerFallbackValue(proto.MyEtapaFluxoIdRequest());
    registerFallbackValue(proto.MoverMyEtapaFluxoRequest());
    registerFallbackValue(proto.ListMyDepartamentosRequest());
    registerFallbackValue(proto.ListMyAtendentesRequest());
  });

  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  Fluxo fluxoCom({
    bool ativo = true,
    int etapas = 4,
    int abertos = 0,
  }) =>
      Fluxo(
        id: 1,
        departamentoId: 1,
        departamentoNome: 'Suporte',
        nome: 'Padrão',
        descricao: '',
        ativo: ativo,
        etapas: etapas,
        atendimentosAbertos: abertos,
      );

  group('regras do fluxo', () {
    test('quadro sem coluna é sinalizado', () {
      // Fluxo sem etapa de entrada não recebe conversa: o roteamento procura a
      // coluna `fila` e não acha, e falha calado.
      expect(fluxoCom(etapas: 0).semEtapas, isTrue);
      expect(fluxoCom().semEtapas, isFalse);
    });

    test('fluxo com conversa aberta não pode ser desativado', () {
      expect(fluxoCom(abertos: 3).podeDesativar, isFalse);
      expect(fluxoCom().podeDesativar, isTrue);
    });

    test('fluxo já inativo não oferece desativar de novo', () {
      expect(fluxoCom(ativo: false).podeDesativar, isFalse);
    });
  });

  group('TipoEtapa', () {
    test('o código do banco vira o tipo', () {
      expect(TipoEtapa.doCodigo('fila'), TipoEtapa.fila);
      expect(TipoEtapa.doCodigo('finalizacao'), TipoEtapa.finalizacao);
    });

    test('tipo desconhecido não derruba a tela', () {
      // A coluna é VARCHAR(20): uma linha antiga com valor fora do vocabulário
      // não deve custar a tela inteira.
      expect(TipoEtapa.doCodigo('inventado'), TipoEtapa.trabalho);
      expect(TipoEtapa.doCodigo(''), TipoEtapa.trabalho);
    });
  });

  group('corDoHex', () {
    test('converte o hex do banco', () {
      expect(corDoHex('#3B82F6'), const Color(0xFF3B82F6));
      expect(corDoHex('3B82F6'), const Color(0xFF3B82F6));
    });

    test('hex inválido cai no cinza em vez de estourar', () {
      expect(corDoHex(''), const Color(0xFF6B7280));
      expect(corDoHex('#xyz'), const Color(0xFF6B7280));
      expect(corDoHex('#12345'), const Color(0xFF6B7280));
    });
  });

  proto.MyFluxo pbFluxo({
    int id = 1,
    String nome = 'Padrão',
    bool ativo = true,
    int etapas = 4,
    int abertos = 0,
  }) =>
      proto.MyFluxo(
        id: id,
        departamentoId: 1,
        departamentoNome: 'Suporte',
        nome: nome,
        ativo: ativo,
        etapas: etapas,
        atendimentosAbertos: abertos,
      );

  proto.MyEtapaFluxo pbEtapa({
    int id = 1,
    String nome = 'Entrada',
    String tipo = 'fila',
    int ordem = 1,
    String cor = '#6B7280',
  }) =>
      proto.MyEtapaFluxo(
        id: id,
        fluxoId: 1,
        nome: nome,
        ordem: ordem,
        cor: cor,
        tipoEtapa: tipo,
        ativo: true,
      );

  void respondeDepartamentos() {
    when(() => client.listMyDepartamentos(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyDepartamentosResponse(
          departamentos: [
            proto.MyDepartamento(id: 1, nome: 'Suporte', ativo: true),
            proto.MyDepartamento(id: 2, nome: 'Antigo', ativo: false),
          ],
        ),
      ),
    );
    when(() => client.listMyAtendentes(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyAtendentesResponse()),
    );
  }

  FluxosController criarControllerDeFluxos() => FluxosController(
        listar: ListarFluxosUsecase(
          repository: ListarFluxosRepository(
            datasource: ListarFluxosDatasource(client: client),
          ),
        ),
        criar: CriarFluxoUsecase(
          repository: CriarFluxoRepository(
            datasource: CriarFluxoDatasource(client: client),
          ),
        ),
        atualizar: AtualizarFluxoUsecase(
          repository: AtualizarFluxoRepository(
            datasource: AtualizarFluxoDatasource(client: client),
          ),
        ),
        desativar: DesativarFluxoUsecase(
          repository: DesativarFluxoRepository(
            datasource: DesativarFluxoDatasource(client: client),
          ),
        ),
        equipe: CarregarEquipeUsecase(
          repository: CarregarEquipeRepository(
            datasource: CarregarEquipeDatasource(client: client),
          ),
        ),
      );

  EtapasFluxoController criarControllerDeEtapas() => EtapasFluxoController(
        listar: ListarEtapasUsecase(
          repository: ListarEtapasRepository(
            datasource: ListarEtapasDatasource(client: client),
          ),
        ),
        criar: CriarEtapaUsecase(
          repository: CriarEtapaRepository(
            datasource: CriarEtapaDatasource(client: client),
          ),
        ),
        atualizar: AtualizarEtapaUsecase(
          repository: AtualizarEtapaRepository(
            datasource: AtualizarEtapaDatasource(client: client),
          ),
        ),
        desativar: DesativarEtapaUsecase(
          repository: DesativarEtapaRepository(
            datasource: DesativarEtapaDatasource(client: client),
          ),
        ),
        mover: MoverEtapaUsecase(
          repository: MoverEtapaRepository(
            datasource: MoverEtapaDatasource(client: client),
          ),
        ),
      );

  void registrarSessao() {
    final auth = _MockAuthService();
    when(() => auth.currentSession).thenReturn(null);
    getIt.registerSingleton<AuthService>(auth);
  }

  Future<GoRouter> montar(WidgetTester tester, Widget tela) async {
    tester.view.physicalSize = const Size(1500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => tela),
        GoRoute(
          path: '/tenant/fluxos/:id/etapas',
          builder: (_, _) => const Scaffold(body: Text('etapas')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
    return router;
  }

  group('FluxosPage', () {
    void registrar() {
      getIt.registerSingleton<FluxosController>(criarControllerDeFluxos());
      registrarSessao();
    }

    void responde(List<proto.MyFluxo> fluxos) {
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyFluxosResponse(fluxos: fluxos)),
      );
      respondeDepartamentos();
    }

    testWidgets('lista os fluxos com departamento e contagens', (tester) async {
      responde([pbFluxo(abertos: 2)]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      expect(find.text('Padrão'), findsOneWidget);
      expect(find.textContaining('Suporte'), findsOneWidget);
      expect(find.textContaining('4 coluna(s)'), findsOneWidget);
      expect(find.textContaining('2 em aberto'), findsOneWidget);
    });

    testWidgets('quadro sem coluna é marcado na lista', (tester) async {
      responde([pbFluxo(etapas: 0)]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      expect(find.text('Sem colunas'), findsOneWidget);
    });

    testWidgets('desativar fica bloqueado com conversa em aberto', (
      tester,
    ) async {
      // Deixar clicar para o servidor recusar seria pedir um erro que já se
      // sabe aqui.
      responde([pbFluxo(abertos: 1)]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      expect(_botaoDeTooltip(tester, 'Tem conversa em aberto neste fluxo'),
          isNull);
    });

    testWidgets('conta sem fluxo explica o que falta', (tester) async {
      responde([]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      expect(find.text('Nenhum fluxo ainda'), findsOneWidget);
    });

    testWidgets('erro do servidor vira tela de erro', (tester) async {
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
      );
      respondeDepartamentos();
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });

    testWidgets('o seletor só oferece departamento ativo', (tester) async {
      // Criar fluxo em departamento desativado deixaria conversa presa num
      // setor que não recebe mais nada.
      responde([]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo fluxo'));
      await tester.pumpAndSettle();

      expect(find.text('Suporte'), findsOneWidget);
      expect(find.text('Antigo'), findsNothing);
    });

    testWidgets('criar fluxo sem nome é barrado dentro da janela', (
      tester,
    ) async {
      responde([]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo fluxo'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome do fluxo.'), findsOneWidget);
      verifyNever(() => client.createMyFluxo(any()));
    });

    testWidgets('criar fluxo fecha a janela e recarrega', (tester) async {
      responde([]);
      when(() => client.createMyFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.MyFluxoResponse(fluxo: pbFluxo())),
      );
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo fluxo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Suporte técnico'),
        'Comercial',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.createMyFluxo(captureAny()))
          .captured
          .single as proto.CreateMyFluxoRequest;
      expect(enviado.nome, 'Comercial');
      expect(enviado.departamentoId, 1);
      // Uma na montagem, outra depois de criar.
      verify(() => client.listMyFluxos(any())).called(2);
    });

    testWidgets('o limite do plano vira mensagem própria', (tester) async {
      // RESOURCE_EXHAUSTED aqui é o teto do plano; traduzir para "tente de
      // novo" mandaria o tenant repetir para sempre.
      responde([]);
      when(() => client.createMyFluxo(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.resourceExhausted('quota')),
      );
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo fluxo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Suporte técnico'),
        'Comercial',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.textContaining('limite de fluxos'), findsOneWidget);
    });

    testWidgets('editar fluxo não deixa trocar de departamento', (
      tester,
    ) async {
      // Mover um fluxo de departamento mudaria o destino de conversas já em
      // andamento — isso não é edição de cadastro.
      responde([pbFluxo()]);
      when(() => client.updateMyFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar'));
      await tester.pumpAndSettle();

      expect(find.text('Departamento'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Suporte técnico'),
        'Padrão renomeado',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.updateMyFluxo(captureAny()))
          .captured
          .single as proto.UpdateMyFluxoRequest;
      expect(enviado.nome, 'Padrão renomeado');
      expect(enviado.ativo, isTrue);
    });

    testWidgets('desativar confirma antes e avisa o resultado', (tester) async {
      responde([pbFluxo()]);
      when(() => client.desativarMyFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Desativar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('para de receber conversas novas'),
          findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Desativar'));
      await tester.pumpAndSettle();

      verify(() => client.desativarMyFluxo(any())).called(1);
      expect(find.text('Fluxo desativado.'), findsOneWidget);
    });

    testWidgets('cancelar a desativação não chama o servidor', (tester) async {
      responde([pbFluxo()]);
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Desativar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => client.desativarMyFluxo(any()));
    });

    testWidgets('sem departamento nenhum, a janela diz o que fazer antes', (
      tester,
    ) async {
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyFluxosResponse()),
      );
      when(() => client.listMyDepartamentos(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyDepartamentosResponse()),
      );
      when(() => client.listMyAtendentes(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyAtendentesResponse()),
      );
      registrar();

      await montar(tester, const FluxosPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo fluxo'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Nenhum departamento ativo'), findsOneWidget);

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();
      verifyNever(() => client.createMyFluxo(any()));
    });
  });

  group('EtapasFluxoPage', () {
    void registrar() {
      getIt.registerSingleton<EtapasFluxoController>(criarControllerDeEtapas());
      registrarSessao();
    }

    void responde(List<proto.MyEtapaFluxo> etapas) {
      when(() => client.listMyEtapasFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMyEtapasFluxoResponse(etapas: etapas)),
      );
    }

    List<proto.MyEtapaFluxo> tresEtapas() => [
          pbEtapa(),
          pbEtapa(id: 2, nome: 'Trabalhando', tipo: 'trabalho', ordem: 2),
          pbEtapa(id: 3, nome: 'Fechado', tipo: 'finalizacao', ordem: 3),
        ];

    testWidgets('lista as colunas na ordem do quadro', (tester) async {
      responde(tresEtapas());
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      expect(find.text('Entrada'), findsOneWidget);
      expect(find.text('Trabalhando'), findsOneWidget);
      expect(find.text('Fechado'), findsOneWidget);
    });

    testWidgets('as pontas não oferecem movimento para fora', (tester) async {
      responde(tresEtapas());
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      final subir = _botoesDeTooltip(tester, 'Mover para cima');
      final descer = _botoesDeTooltip(tester, 'Mover para baixo');
      expect(subir.first.onPressed, isNull);
      expect(subir.last.onPressed, isNotNull);
      expect(descer.last.onPressed, isNull);
      expect(descer.first.onPressed, isNotNull);
    });

    testWidgets('mover manda a direção e recarrega', (tester) async {
      responde(tresEtapas());
      when(() => client.moverMyEtapaFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mover para cima').last);
      await tester.pumpAndSettle();

      final enviado = verify(() => client.moverMyEtapaFluxo(captureAny()))
          .captured
          .single as proto.MoverMyEtapaFluxoRequest;
      expect(enviado.id, 3);
      expect(enviado.paraCima, isTrue);
      verify(() => client.listMyEtapasFluxo(any())).called(2);
    });

    testWidgets('mover na ponta não recarrega a lista à toa', (tester) async {
      // `sucesso: false` é "já está na ponta", não falha: recarregar por isso
      // seria uma ida ao servidor para redesenhar a mesma tela.
      responde(tresEtapas());
      when(() => client.moverMyEtapaFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: false)),
      );
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Mover para baixo').first);
      await tester.pumpAndSettle();

      verify(() => client.listMyEtapasFluxo(any())).called(1);
    });

    testWidgets('a nova coluna mostra o que o tipo significa', (tester) async {
      // O tipo não é rótulo: é o que o roteamento lê para saber onde a conversa
      // entra e quando o atendimento termina.
      responde(tresEtapas());
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nova coluna'));
      await tester.pumpAndSettle();

      expect(find.text('Alguém está cuidando agora'), findsOneWidget);
    });

    testWidgets('criar coluna manda o tipo e a cor escolhidos', (tester) async {
      responde(tresEtapas());
      when(() => client.createMyEtapaFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.MyEtapaFluxoResponse(etapa: pbEtapa(id: 9))),
      );
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nova coluna'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Aguardando pagamento'),
        'Aguardando NF',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.createMyEtapaFluxo(captureAny()))
          .captured
          .single as proto.CreateMyEtapaFluxoRequest;
      expect(enviado.nome, 'Aguardando NF');
      expect(enviado.tipoEtapa, 'trabalho');
      expect(enviado.fluxoId, 1);
      expect(enviado.cor, coresDeEtapa.first);
    });

    testWidgets('coluna sem nome é barrada dentro da janela', (tester) async {
      responde(tresEtapas());
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nova coluna'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      expect(find.text('Informe o nome da coluna.'), findsOneWidget);
      verifyNever(() => client.createMyEtapaFluxo(any()));
    });

    testWidgets('a recusa do servidor chega inteira ao operador', (
      tester,
    ) async {
      // A última fila de entrada e a coluna ocupada só o servidor sabe; o
      // motivo tem de chegar escrito, não virar "algo deu errado".
      responde(tresEtapas());
      when(() => client.desativarMyEtapaFluxo(any())).thenAnswer(
        (_) => falhaGrpc(
          proto.GrpcError.invalidArgument(
            'Esta é a única fila de entrada do fluxo.',
          ),
        ),
      );
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remover').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();

      expect(
        find.text('Esta é a única fila de entrada do fluxo.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelar a remoção não chama o servidor', (tester) async {
      responde(tresEtapas());
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remover').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => client.desativarMyEtapaFluxo(any()));
    });


    testWidgets('editar coluna leva a descrição e o tipo escolhidos', (
      tester,
    ) async {
      responde(tresEtapas());
      when(() => client.updateMyEtapaFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar').first);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'ex: Esperando o cliente enviar o '
            'comprovante'),
        'Entra por aqui',
      );
      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      final enviado = verify(() => client.updateMyEtapaFluxo(captureAny()))
          .captured
          .single as proto.UpdateMyEtapaFluxoRequest;
      expect(enviado.id, 1);
      expect(enviado.descricao, 'Entra por aqui');
      // O tipo original é preservado quando não se mexe nele.
      expect(enviado.tipoEtapa, 'fila');
    });

    testWidgets('remover coluna avisa que o histórico fica', (tester) async {
      responde(tresEtapas());
      when(() => client.desativarMyEtapaFluxo(any())).thenAnswer(
        (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
      );
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remover').first);
      await tester.pumpAndSettle();
      expect(find.textContaining('histórico'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
      await tester.pumpAndSettle();

      expect(find.text('Coluna removida.'), findsOneWidget);
    });

    testWidgets('fluxo sem coluna avisa que não recebe conversa', (
      tester,
    ) async {
      responde([]);
      registrar();

      await montar(tester, const EtapasFluxoPage(fluxoId: 1));
      await tester.pumpAndSettle();

      expect(find.text('Nenhuma coluna'), findsOneWidget);
    });
  });

  test('sessão expirada é distinguida de servidor fora do ar', () async {
    when(() => client.listMyFluxos(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.unauthenticated('expirou')),
    );

    final res = await ListarFluxosUsecase(
      repository: ListarFluxosRepository(
        datasource: ListarFluxosDatasource(client: client),
      ),
    )(noParams);

    expect((res as Failure).error, isA<FluxosAcessoNegado>());
  });

  test('item que sumiu não vira erro de rede', () async {
    when(() => client.desativarMyFluxo(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.notFound('sumiu')),
    );

    final res = await DesativarFluxoUsecase(
      repository: DesativarFluxoRepository(
        datasource: DesativarFluxoDatasource(client: client),
      ),
    )(const FluxoIdParameters(id: 1));

    expect((res as Failure).error, isA<FluxoNaoEncontrado>());
  });
}
