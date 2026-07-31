// A configuração inicial guiada — o roteiro que tira o tenant de "conta
// criada" para "atendimento funcionando".
//
// O caso que mais importa aqui é o limite do plano: o servidor recusa a criação
// de instância com RESOURCE_EXHAUSTED quando `max_instances` do plano esgotou,
// e traduzir isso para "servidor indisponível" mandaria o cliente tentar de novo
// para sempre.
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onboarding_module/src/features/configuracao/data/datasources/configuracao_datasources.dart';
import 'package:onboarding_module/src/features/configuracao/data/repositories/configuracao_repositories.dart';
import 'package:onboarding_module/src/features/configuracao/domain/errors/configuracao_errors.dart';
import 'package:onboarding_module/src/features/configuracao/domain/model/configuracao_models.dart';
import 'package:onboarding_module/src/features/configuracao/domain/parameters/configuracao_parameters.dart';
import 'package:onboarding_module/src/features/configuracao/domain/usecases/configuracao_usecases.dart';
import 'package:onboarding_module/src/features/configuracao/presentation/controllers/configuracao_controllers.dart';
import 'package:onboarding_module/src/features/configuracao/presentation/pages/conexao_whatsapp_page.dart';
import 'package:onboarding_module/src/features/configuracao/presentation/pages/departamento_page.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

class _MockAdmin extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdmin client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.CreateMyWhatsappInstanceRequest());
    registerFallbackValue(proto.GetMyWhatsappInstanceStatusRequest());
    registerFallbackValue(proto.CreateMyDepartamentoRequest());
    registerFallbackValue(proto.SetMyBotPersonaRequest());
    registerFallbackValue(proto.SetOnboardingProgressRequest());
  });

  setUp(() => client = _MockAdmin());
  tearDown(() => getIt.reset());

  /// O progresso é registrado ao fim de cada passo; sem este stub, avançar
  /// quebraria em todos os testes.
  void progressoResponde() {
    when(() => client.setOnboardingProgress(any())).thenAnswer(
      (_) => respostaGrpc(proto.SetOnboardingProgressResponse()),
    );
  }

  CriarConexaoUsecase criarConexao() => CriarConexaoUsecase(
    repository: CriarConexaoRepository(
      datasource: CriarConexaoDatasource(client: client),
    ),
  );
  EstadoConexaoUsecase estadoConexao() => EstadoConexaoUsecase(
    repository: EstadoConexaoRepository(
      datasource: EstadoConexaoDatasource(client: client),
    ),
  );
  ProgressoUsecase progresso() => ProgressoUsecase(
    repository: ProgressoRepository(
      datasource: ProgressoDatasource(client: client),
    ),
  );

  Future<void> montar(WidgetTester tester, Widget pagina) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => pagina),
        GoRoute(
          path: '/configuracao/whatsapp',
          builder: (_, _) => const Text('passo whatsapp'),
        ),
        GoRoute(
          path: '/configuracao/departamento',
          builder: (_, _) => const Text('passo setor'),
        ),
        GoRoute(
          path: '/configuracao/assistente',
          builder: (_, _) => const Text('passo assistente'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  group('limite do plano', () {
    test('recusa por quota vira LimiteDoPlanoAtingido, não indisponibilidade',
        () async {
      // O teto vem do plano do tenant (`tenants_plan.max_instances`), não de um
      // número no código. A tela precisa dizer que o caminho é mudar de plano —
      // insistir não resolve.
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => falhaGrpc<proto.CreateMyWhatsappInstanceResponse>(
          proto.GrpcError.resourceExhausted(),
        ),
      );

      final res = await criarConexao()(
        const CriarConexaoParameters(nome: 'Comercial'),
      );

      expect(
        (res as Failure<ConexaoWhatsapp, ConfiguracaoError>).error,
        isA<LimiteDoPlanoAtingido>(),
      );
    });

    test('nome duplicado explica o que fazer', () async {
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => falhaGrpc<proto.CreateMyWhatsappInstanceResponse>(
          proto.GrpcError.alreadyExists(),
        ),
      );

      final res = await criarConexao()(
        const CriarConexaoParameters(nome: 'Comercial'),
      );
      final erro = (res as Failure<ConexaoWhatsapp, ConfiguracaoError>).error;

      expect(erro, isA<ConfiguracaoDadosInvalidos>());
      expect(erro.message, contains('outro'));
    });
  });

  group('CriarConexaoUsecase', () {
    test('conexão sem id é falha — não haveria o que consultar', () async {
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateMyWhatsappInstanceResponse(id: 0, instanceName: 'x'),
        ),
      );

      final res = await criarConexao()(
        const CriarConexaoParameters(nome: 'x'),
      );

      expect(res, isA<Failure<ConexaoWhatsapp, ConfiguracaoError>>());
    });
  });

  group('ConexaoWhatsappPage', () {
    void registrar() {
      getIt.registerSingleton<ConexaoController>(
        ConexaoController(
          criar: criarConexao(),
          estado: estadoConexao(),
          progresso: progresso(),
        ),
      );
    }

    testWidgets('começa pedindo o nome da conexão', (tester) async {
      registrar();
      await montar(tester, const ConexaoWhatsappPage());

      expect(find.text('Conectar o WhatsApp'), findsOneWidget);
      expect(find.text('Nome desta conexão'), findsOneWidget);
      expect(find.text('Gerar QR Code'), findsOneWidget);
    });

    testWidgets('dá para adiar — parear exige o celular em mãos', (
      tester,
    ) async {
      // Bloquear aqui deixaria preso quem instalou o programa mas não está com
      // o telefone.
      progressoResponde();
      registrar();
      await montar(tester, const ConexaoWhatsappPage());

      await tester.tap(find.text('Fazer isso depois'));
      await tester.pumpAndSettle();

      expect(find.text('passo setor'), findsOneWidget);
      // O avanço foi registrado no servidor, para a retomada saber onde parou.
      verify(() => client.setOnboardingProgress(any())).called(1);
    });

    testWidgets('limite do plano aparece na tela', (tester) async {
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => falhaGrpc<proto.CreateMyWhatsappInstanceResponse>(
          proto.GrpcError.resourceExhausted(),
        ),
      );
      registrar();
      await montar(tester, const ConexaoWhatsappPage());

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome desta conexão'),
        'Comercial',
      );
      await tester.tap(find.text('Gerar QR Code'));
      await tester.pumpAndSettle();

      expect(find.textContaining('limite de conexões'), findsOneWidget);
    });

    testWidgets('conexão criada mostra o QR e espera a leitura', (
      tester,
    ) async {
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateMyWhatsappInstanceResponse(id: 7, instanceName: 'c'),
        ),
      );
      when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetMyWhatsappInstanceStatusResponse(
            connectionState: 'connecting',
            qrCode: '',
          ),
        ),
      );
      registrar();
      await montar(tester, const ConexaoWhatsappPage());

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome desta conexão'),
        'Comercial',
      );
      await tester.tap(find.text('Gerar QR Code'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Aparelhos conectados'), findsOneWidget);
      expect(find.textContaining('Aguardando a leitura'), findsOneWidget);
    });

    testWidgets('pareado, oferece seguir', (tester) async {
      when(() => client.createMyWhatsappInstance(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateMyWhatsappInstanceResponse(id: 7, instanceName: 'c'),
        ),
      );
      when(() => client.getMyWhatsappInstanceStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetMyWhatsappInstanceStatusResponse(
            connectionState: 'connected',
          ),
        ),
      );
      registrar();
      await montar(tester, const ConexaoWhatsappPage());

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome desta conexão'),
        'Comercial',
      );
      await tester.tap(find.text('Gerar QR Code'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('WhatsApp conectado'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
    });
  });

  group('DepartamentoPage', () {
    testWidgets('sugere um nome pronto e avança ao criar', (tester) async {
      // Partir de um campo vazio trava; aceitar o padrão é um clique.
      when(() => client.createMyDepartamento(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateMyDepartamentoResponse(id: 1, nome: 'Atendimento'),
        ),
      );
      progressoResponde();
      getIt.registerSingleton<DepartamentoController>(
        DepartamentoController(
          criar: CriarDepartamentoUsecase(
            repository: CriarDepartamentoRepository(
              datasource: CriarDepartamentoDatasource(client: client),
            ),
          ),
          progresso: progresso(),
        ),
      );
      await montar(tester, const DepartamentoPage());

      expect(find.text('Atendimento'), findsOneWidget);

      await tester.tap(find.text('Criar setor'));
      await tester.pumpAndSettle();

      expect(find.text('passo assistente'), findsOneWidget);
    });
  });
}
