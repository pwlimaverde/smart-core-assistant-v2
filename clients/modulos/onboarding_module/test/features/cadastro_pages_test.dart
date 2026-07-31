// Renderização das quatro telas do wizard.
//
// Cada teste monta a página com o controller real sobre o stub gRPC mockado —
// exercita a cadeia inteira (datasource → repository → usecase → controller) e
// confere o que a tela promete a quem está criando a conta.
import 'package:api_client/api_client.dart' as proto;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onboarding_module/src/features/cadastro/data/datasources/cadastro_datasources.dart';
import 'package:onboarding_module/src/features/cadastro/data/repositories/cadastro_repositories.dart';
import 'package:onboarding_module/src/features/cadastro/domain/services/cadastro_sessao.dart';
import 'package:onboarding_module/src/features/cadastro/domain/usecases/cadastro_usecases.dart';
import 'package:onboarding_module/src/features/cadastro/presentation/controllers/cadastro_controllers.dart';
import 'package:onboarding_module/src/features/cadastro/presentation/pages/cadastro_dados_page.dart';
import 'package:onboarding_module/src/features/cadastro/presentation/pages/cadastro_pagamento_page.dart';
import 'package:onboarding_module/src/features/cadastro/presentation/pages/cadastro_plano_page.dart';
import 'package:onboarding_module/src/features/cadastro/presentation/pages/cadastro_pronto_page.dart';
import 'package:login_module/login_module.dart' as login;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../support/onboarding_grpc_mock.dart';

void main() {
  late MockOnboardingClient client;
  late CadastroSessao sessao;
  final getIt = GetIt.instance;

  setUpAll(registrarFallbacksDoCadastro);

  setUp(() {
    client = MockOnboardingClient();
    sessao = CadastroSessao();
  });

  tearDown(() => getIt.reset());

  Future<void> montar(WidgetTester tester, Widget pagina) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => pagina),
        // Destinos possíveis dos redirecionamentos do wizard.
        GoRoute(path: '/cadastro', builder: (_, _) => const Text('passo 1')),
        GoRoute(
          path: '/cadastro/plano',
          builder: (_, _) => const Text('passo 2'),
        ),
        GoRoute(
          path: '/cadastro/pagamento',
          builder: (_, _) => const Text('passo 3'),
        ),
        GoRoute(
          path: '/cadastro/pronto',
          builder: (_, _) => const Text('passo 4'),
        ),
        GoRoute(path: '/login', builder: (_, _) => const Text('login')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  group('CadastroDadosPage', () {
    void registrar() {
      getIt.registerSingleton<DadosController>(
        DadosController(
          iniciar: IniciarCadastroUsecase(
            repository: IniciarCadastroRepository(
              datasource: IniciarCadastroDatasource(client: client),
            ),
          ),
          verificarSlug: VerificarSlugUsecase(
            repository: VerificarSlugRepository(
              datasource: VerificarSlugDatasource(client: client),
            ),
          ),
          sessao: sessao,
        ),
      );
    }

    testWidgets('apresenta o formulário do primeiro passo', (tester) async {
      registrar();
      await montar(tester, const CadastroDadosPage());

      expect(find.text('Criar conta'), findsOneWidget);
      expect(find.text('Nome da empresa'), findsOneWidget);
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.text('Já tenho conta'), findsOneWidget);
    });

    testWidgets('cadastro aceito guarda a identidade na sessão', (
      tester,
    ) async {
      when(() => client.checkSlug(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CheckSlugResponse(disponivel: true, motivo: '', mensagem: ''),
        ),
      );
      when(() => client.startSignup(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.StartSignupResponse(
            tenantId: 'tenant-abc',
            signupToken: 'TOKEN123',
            proximoPasso: 2,
          ),
        ),
      );
      registrar();
      await montar(tester, const CadastroDadosPage());

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome da empresa'),
        'Empresa Teste',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail do responsável'),
        'dono@empresa.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha (mínimo 8 caracteres)'),
        'senhaforte8',
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      expect(sessao.tenantId, 'tenant-abc');
      expect(sessao.signupToken, 'TOKEN123');
      // O e-mail fica para o login automático do passo 4.
      expect(sessao.email, 'dono@empresa.com');
    });

    testWidgets('recusa do servidor aparece na tela', (tester) async {
      when(() => client.checkSlug(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CheckSlugResponse(disponivel: true, motivo: '', mensagem: ''),
        ),
      );
      when(() => client.startSignup(any())).thenAnswer(
        (_) => falhaGrpc<proto.StartSignupResponse>(
          proto.GrpcError.invalidArgument('Este endereço já está em uso.'),
        ),
      );
      registrar();
      await montar(tester, const CadastroDadosPage());

      await tester.enterText(
        find.widgetWithText(TextField, 'Nome da empresa'),
        'Empresa',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'E-mail do responsável'),
        'a@b.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Senha (mínimo 8 caracteres)'),
        'senhaforte8',
      );
      await tester.tap(find.text('Continuar'));
      await tester.pumpAndSettle();

      // A mensagem do servidor chega ao usuário: é ele quem sabe por que o
      // endereço foi recusado.
      expect(find.text('Este endereço já está em uso.'), findsOneWidget);
      expect(sessao.iniciado, isFalse);
    });
  });

  group('CadastroPlanoPage', () {
    void registrar() {
      getIt.registerSingleton<CadastroSessao>(sessao);
      getIt.registerSingleton<PlanoController>(
        PlanoController(
          listar: ListarPlanosUsecase(
            repository: ListarPlanosRepository(
              datasource: ListarPlanosDatasource(client: client),
            ),
          ),
          selecionar: SelecionarPlanoUsecase(
            repository: SelecionarPlanoRepository(
              datasource: SelecionarPlanoDatasource(client: client),
            ),
          ),
          sessao: sessao,
        ),
      );
    }

    testWidgets('mostra os limites do plano', (tester) async {
      sessao.registrarInicio(tenantId: 't-1', signupToken: 'TOK');
      when(() => client.listPublicPlans(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListPublicPlansResponse(planos: [planoBasico()]),
        ),
      );
      registrar();
      await montar(tester, const CadastroPlanoPage());
      await tester.pumpAndSettle();

      expect(find.text('Básico'), findsOneWidget);
      expect(find.text('3 WhatsApp'), findsOneWidget);
      expect(find.text('5 fluxos'), findsOneWidget);
      // Preço vazio: dizer "a combinar" é mais honesto que exibir R$ 0,00.
      expect(find.text('a combinar'), findsOneWidget);
    });

    testWidgets('sem passo 1 concluído, volta para o começo', (tester) async {
      // O `signup_token` vive só em memória; chegar aqui por link direto ou
      // recarga não tem como funcionar.
      registrar();
      await montar(tester, const CadastroPlanoPage());
      await tester.pumpAndSettle();

      expect(find.text('passo 1'), findsOneWidget);
      verifyNever(() => client.listPublicPlans(any()));
    });
  });

  group('CadastroPagamentoPage', () {
    void registrar() {
      getIt.registerSingleton<CadastroSessao>(sessao);
      getIt.registerSingleton<PagamentoController>(
        PagamentoController(
          listar: ListarProvedoresUsecase(
            repository: ListarProvedoresRepository(
              datasource: ListarProvedoresDatasource(client: client),
            ),
          ),
          confirmar: ConfirmarPagamentoUsecase(
            repository: ConfirmarPagamentoRepository(
              datasource: ConfirmarPagamentoDatasource(client: client),
            ),
          ),
          sessao: sessao,
        ),
      );
    }

    void sessaoPronta() {
      sessao
        ..registrarInicio(tenantId: 't-1', signupToken: 'TOK')
        ..registrarPlano(1);
    }

    testWidgets('com um provedor só, mostra direto o campo do código', (
      tester,
    ) async {
      sessaoPronta();
      when(() => client.listPaymentProviders(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListPaymentProvidersResponse(provedores: [provedorVoucher()]),
        ),
      );
      registrar();
      await montar(tester, const CadastroPagamentoPage());
      await tester.pumpAndSettle();

      expect(find.text('Código'), findsOneWidget);
      expect(find.text('Confirmar'), findsOneWidget);
    });

    testWidgets('código recusado mostra a mensagem e não avança', (
      tester,
    ) async {
      sessaoPronta();
      when(() => client.listPaymentProviders(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListPaymentProvidersResponse(provedores: [provedorVoucher()]),
        ),
      );
      when(() => client.confirmPayment(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ConfirmPaymentResponse(
            confirmado: false,
            motivo: 'expirado',
            mensagem: 'Este código expirou.',
          ),
        ),
      );
      registrar();
      await montar(tester, const CadastroPagamentoPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Código'),
        'DEVTESTE',
      );
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      // Recusa é resposta, não erro: o usuário fica na tela e pode tentar
      // outro código.
      expect(find.text('Este código expirou.'), findsOneWidget);
      expect(find.text('passo 4'), findsNothing);
    });

    testWidgets('código aceito leva para a conclusão', (tester) async {
      sessaoPronta();
      when(() => client.listPaymentProviders(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListPaymentProvidersResponse(provedores: [provedorVoucher()]),
        ),
      );
      when(() => client.confirmPayment(any())).thenAnswer(
        (_) => respostaGrpc(proto.ConfirmPaymentResponse(confirmado: true)),
      );
      registrar();
      await montar(tester, const CadastroPagamentoPage());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Código'),
        'DEVTESTE',
      );
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(find.text('passo 4'), findsOneWidget);
    });

    testWidgets('sem plano escolhido, volta para o passo 2', (tester) async {
      sessao.registrarInicio(tenantId: 't-1', signupToken: 'TOK');
      registrar();
      await montar(tester, const CadastroPagamentoPage());
      await tester.pumpAndSettle();

      expect(find.text('passo 2'), findsOneWidget);
      verifyNever(() => client.listPaymentProviders(any()));
    });
  });

  group('CadastroProntoPage', () {
    void registrar() {
      final auth = _AuthFalso();
      when(
        () => auth.login(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => Success(_sessaoDeTeste()));

      getIt.registerSingleton<CadastroSessao>(sessao);
      getIt.registerSingleton<ConclusaoController>(
        ConclusaoController(
          status: StatusCadastroUsecase(
            repository: StatusCadastroRepository(
              datasource: StatusCadastroDatasource(client: client),
            ),
          ),
          sessao: sessao,
          auth: auth,
        ),
      );
    }

    testWidgets('conta liberada oferece a entrada', (tester) async {
      sessao
        ..registrarInicio(tenantId: 't-1', signupToken: 'TOK')
        ..registrarCredenciais(email: 'a@b.com', senha: 'senhaforte8');
      when(() => client.getSignupStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetSignupStatusResponse(
            passo: 4,
            planId: 1,
            statusAssinatura: 'ACTIVE',
            tenantAtivo: true,
          ),
        ),
      );
      registrar();
      await montar(tester, const CadastroProntoPage());
      await tester.pumpAndSettle();

      // "Continuar", e não "Entrar": o roteiro não acaba aqui — emenda na
      // configuração inicial, que é o que põe o sistema para operar.
      expect(find.text('Continuar'), findsOneWidget);
      expect(find.textContaining('Conta liberada'), findsOneWidget);
    });

    testWidgets('pagamento pendente mantém a tela de espera', (tester) async {
      // É o caminho do gateway: a confirmação chega depois, por webhook.
      sessao.registrarInicio(tenantId: 't-1', signupToken: 'TOK');
      when(() => client.getSignupStatus(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetSignupStatusResponse(
            passo: 3,
            planId: 1,
            statusAssinatura: 'PENDING_PAYMENT',
            tenantAtivo: false,
          ),
        ),
      );
      registrar();
      await montar(tester, const CadastroProntoPage());
      await tester.pump();

      expect(find.textContaining('Aguardando a confirmação'), findsOneWidget);
      expect(find.text('Continuar'), findsNothing);
    });

  });

  group('slugSugerido', () {
    test('normaliza acentos e separadores', () {
      expect(slugSugerido('Padaria São João'), 'padaria-sao-joao');
      expect(slugSugerido('  Açaí & Cia.  '), 'acai-cia');
      expect(slugSugerido('Loja 123'), 'loja-123');
    });

    test('não deixa hífen sobrando nas pontas nem repetido', () {
      expect(slugSugerido('--Empresa--'), 'empresa');
      expect(slugSugerido('A   B'), 'a-b');
    });
  });
}

/// `AuthService` de teste — o wizard só usa o `login`.
class _AuthFalso extends Mock implements login.AuthService {}

login.Session _sessaoDeTeste() => login.Session(
  accessToken: 'a',
  refreshToken: 'r',
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
  tenantId: 't-1',
  scopes: const ['tenant:admin'],
  isSuperuser: false,
);
