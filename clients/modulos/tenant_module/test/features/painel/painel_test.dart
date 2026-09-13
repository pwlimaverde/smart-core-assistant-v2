import 'package:api_client/api_client.dart' as proto;
import 'package:dependencies_module/dependencies_module.dart'
    show LocalStorageService;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:login_module/login_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/integracoes/data/datasources/integracoes_datasources.dart';
import 'package:tenant_module/src/features/integracoes/data/repositories/integracoes_repositories.dart';
import 'package:tenant_module/src/features/integracoes/domain/usecases/integracoes_usecases.dart';
import 'package:tenant_module/src/features/integracoes/presentation/widgets/convite_agentes.dart';
import 'package:tenant_module/src/features/painel/data/datasources/painel_datasources.dart';
import 'package:tenant_module/src/features/painel/data/repositories/painel_repositories.dart';
import 'package:tenant_module/src/features/painel/domain/errors/painel_errors.dart';
import 'package:tenant_module/src/features/painel/domain/model/painel.dart';
import 'package:tenant_module/src/features/painel/domain/usecases/painel_usecases.dart';
import 'package:tenant_module/src/features/painel/presentation/controllers/painel_controllers.dart';
import 'package:tenant_module/src/features/painel/presentation/pages/painel_page.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

class _MockAuthService extends Mock implements AuthService {}

/// Armazenamento em memória: o real é o secure storage do login.
final class _Memoria implements LocalStorageService {
  final dados = <String, String>{};

  @override
  Future<void> init() async {}

  @override
  String? read(String key) => dados[key];

  @override
  Future<void> write(String key, String value) async => dados[key] = value;

  @override
  Future<void> delete(String key) async => dados.remove(key);
}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.GetMyPainelRequest());
    registerFallbackValue(proto.ListMcpGrantsRequest());
  });
  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  Painel painelCom({
    int aguardando = 0,
    int emAndamento = 0,
    int conexoesAtivas = 1,
    int conexoesTotal = 1,
    int departamentos = 1,
  }) => Painel(
    emAndamento: emAndamento,
    aguardando: aguardando,
    mensagens24h: 0,
    conexoesAtivas: conexoesAtivas,
    conexoesTotal: conexoesTotal,
    departamentos: departamentos,
    treinamentosAtivos: 0,
  );

  group('leitura dos números', () {
    test('conexão caída é detectada pela diferença, não por um flag', () {
      // O servidor manda ativas e total; derivar aqui evita um campo a mais no
      // contrato que poderia divergir dos números.
      expect(
        painelCom(conexoesAtivas: 1, conexoesTotal: 2).temConexaoCaida,
        isTrue,
      );
      expect(
        painelCom(conexoesAtivas: 2, conexoesTotal: 2).temConexaoCaida,
        isFalse,
      );
    });

    test('conta nova, sem nada configurado, não conta como conexão caída', () {
      // 0 de 0 não é queda — é conta nova, e o aviso tem de ser outro.
      final novo = painelCom(
        conexoesAtivas: 0,
        conexoesTotal: 0,
        departamentos: 0,
      );
      expect(novo.temConexaoCaida, isFalse);
      expect(novo.faltaEstrutura, isTrue);
    });

    test('departamento faltando também é falta de estrutura', () {
      expect(painelCom(departamentos: 0).faltaEstrutura, isTrue);
      expect(painelCom().faltaEstrutura, isFalse);
    });
  });

  group('convite para agentes (B8)', () {
    test('só convida quem tem zero conectados e não dispensou', () {
      expect(deveConvidarParaAgentes(dispensado: false, conectados: 0), isTrue);
      expect(deveConvidarParaAgentes(dispensado: true, conectados: 0), isFalse);
      // Quem já tem agente conectado nunca vê o cartão.
      expect(
        deveConvidarParaAgentes(dispensado: false, conectados: 1),
        isFalse,
      );
      // Lista que não carregou não é "zero": na dúvida, não insiste.
      expect(
        deveConvidarParaAgentes(dispensado: false, conectados: null),
        isFalse,
      );
    });

    test('o dispensado é por usuário, não por tenant', () {
      expect(
        chaveConviteAgentesDispensado(7),
        isNot(chaveConviteAgentesDispensado(8)),
      );
    });
  });

  group('PainelPage', () {
    void registrar() {
      getIt.registerSingleton<PainelController>(
        PainelController(
          carregar: CarregarPainelUsecase(
            repository: CarregarPainelRepository(
              datasource: CarregarPainelDatasource(client: client),
            ),
          ),
        ),
      );
      final auth = _MockAuthService();
      when(() => auth.currentSession).thenReturn(null);
      getIt.registerSingleton<AuthService>(auth);
    }

    void responde(proto.GetMyPainelResponse r) {
      when(() => client.getMyPainel(any())).thenAnswer((_) => respostaGrpc(r));
    }

    Future<GoRouter> montar(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const PainelPage()),
          GoRoute(
            path: '/tenant/conexoes',
            builder: (_, _) => const Scaffold(body: Text('conexoes')),
          ),
          GoRoute(
            path: '/tenant/equipe',
            builder: (_, _) => const Scaffold(body: Text('equipe')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pump();
      return router;
    }

    testWidgets('mostra os números da operação', (tester) async {
      responde(
        proto.GetMyPainelResponse(
          emAndamento: 3,
          aguardando: 7,
          mensagens24h: 142,
          conexoesAtivas: 2,
          conexoesTotal: 2,
          departamentos: 2,
          treinamentosAtivos: 5,
        ),
      );
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.text('7'), findsOneWidget);
      expect(find.text('142'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
    });

    testWidgets('conexão caída vira aviso com caminho para resolver', (
      tester,
    ) async {
      // Dizer o problema sem oferecer o caminho deixaria a pessoa procurando
      // no menu.
      responde(
        proto.GetMyPainelResponse(
          conexoesAtivas: 1,
          conexoesTotal: 2,
          departamentos: 1,
        ),
      );
      registrar();

      final router = await montar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('conexão de WhatsApp caiu'), findsOneWidget);

      await tester.tap(find.text('Ver conexões'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/tenant/conexoes',
      );
    });

    testWidgets('conta nova é convidada a conectar o WhatsApp', (tester) async {
      responde(proto.GetMyPainelResponse());
      registrar();

      final router = await montar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Falta terminar'), findsOneWidget);
      expect(find.textContaining('Nenhum WhatsApp'), findsOneWidget);

      await tester.tap(find.text('Conectar WhatsApp'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/tenant/conexoes',
      );
    });

    testWidgets('com WhatsApp e sem departamento, aponta o departamento', (
      tester,
    ) async {
      responde(proto.GetMyPainelResponse(conexoesAtivas: 1, conexoesTotal: 1));
      registrar();

      final router = await montar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('não tem para onde mandar'), findsOneWidget);

      await tester.tap(find.text('Criar departamento'));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        '/tenant/equipe',
      );
    });

    /// B8 — registra o que o cartão de agentes precisa, com a sessão do
    /// usuário 7.
    _Memoria registrarConvite(List<proto.McpGrantItem> grants) {
      when(() => client.listMcpGrants(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListMcpGrantsResponse(grants: grants)),
      );
      getIt.registerSingleton<ListMcpGrantsUsecase>(
        ListMcpGrantsUsecase(
          repository: ListMcpGrantsRepository(
            datasource: ListMcpGrantsDatasource(client: client),
          ),
        ),
      );
      final memoria = _Memoria();
      getIt.registerSingleton<LocalStorageService>(memoria);
      final auth = getIt<AuthService>();
      when(() => auth.currentSession).thenReturn(
        Session(
          accessToken: 'a',
          refreshToken: 'r',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          tenantId: 't',
          scopes: const ['atendimentos:read'],
          isSuperuser: false,
          userId: 7,
        ),
      );
      return memoria;
    }

    void respondeSaudavel() => responde(
      proto.GetMyPainelResponse(
        conexoesAtivas: 1,
        conexoesTotal: 1,
        departamentos: 1,
      ),
    );

    testWidgets('sem agente conectado, convida; dispensado, não volta', (
      tester,
    ) async {
      respondeSaudavel();
      registrar();
      final memoria = registrarConvite(const []);

      await montar(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Ligue um assistente de IA à sua conta'),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Dispensar'));
      await tester.pumpAndSettle();
      expect(find.text('Ligue um assistente de IA à sua conta'), findsNothing);
      expect(memoria.dados[chaveConviteAgentesDispensado(7)], '1');

      // Reabrir o painel: o cartão dispensado não volta.
      await tester.pumpWidget(const SizedBox.shrink());
      await montar(tester);
      await tester.pumpAndSettle();
      expect(find.text('Ligue um assistente de IA à sua conta'), findsNothing);
    });

    testWidgets('quem já tem agente conectado não vê o convite', (
      tester,
    ) async {
      respondeSaudavel();
      registrar();
      registrarConvite([
        proto.McpGrantItem(id: 'g-1', clientName: 'Claude', scopes: ['a']),
      ]);

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.text('Ligue um assistente de IA à sua conta'), findsNothing);
    });

    testWidgets('operação saudável não mostra aviso nenhum', (tester) async {
      responde(
        proto.GetMyPainelResponse(
          conexoesAtivas: 1,
          conexoesTotal: 1,
          departamentos: 1,
        ),
      );
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('caiu'), findsNothing);
      expect(find.textContaining('Falta terminar'), findsNothing);
    });

    testWidgets('erro do servidor vira tela de erro', (tester) async {
      when(
        () => client.getMyPainel(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')));
      registrar();

      await montar(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('Não foi possível'), findsOneWidget);
    });

    test('sessão expirada é distinguida de servidor fora do ar', () async {
      when(() => client.getMyPainel(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unauthenticated('expirou')),
      );

      final res = await CarregarPainelUsecase(
        repository: CarregarPainelRepository(
          datasource: CarregarPainelDatasource(client: client),
        ),
      )(noParams);

      expect((res as Failure).error, isA<PainelSessaoExpirada>());
    });
  });
}
