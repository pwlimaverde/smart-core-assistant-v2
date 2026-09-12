import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:app_config/app_config.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:login_module/login_module.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/features/convites/data/datasources/convites_datasources.dart';
import 'package:tenant_module/src/features/convites/data/repositories/convites_repositories.dart';
import 'package:tenant_module/src/features/convites/domain/usecases/convites_usecases.dart';
import 'package:tenant_module/src/features/convites/presentation/controllers/invites_controller.dart';
import 'package:tenant_module/src/features/convites/presentation/pages/invites_page.dart';

import '../../support/admin_client_mock.dart';

class _MockAuthService extends Mock implements AuthService {}

/// A tela de convites — a que o teste de campo reprovou três vezes seguidas.
void main() {
  late MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(registrarFallbacksDoTenant);
  setUp(() => client = MockAdminClient());
  tearDown(() => getIt.reset());

  void registrar() {
    getIt.registerSingleton<InvitesController>(
      InvitesController(
        listUsecase: ListInvitesUsecase(
          repository: ListInvitesRepository(
            datasource: ListInvitesDatasource(client: client),
          ),
        ),
        createUsecase: CreateInviteUsecase(
          repository: CreateInviteRepository(
            datasource: CreateInviteDatasource(client: client),
          ),
        ),
        revokeUsecase: RevokeInviteUsecase(
          repository: RevokeInviteRepository(
            datasource: RevokeInviteDatasource(client: client),
          ),
        ),
      ),
    );
    getIt.registerSingleton<AppConfig>(
      AppConfig(
        flavor: AppFlavor.dev,
        apiEndpoint: 'https://dev.exemplo.com.br',
        mcpEndpoint: 'https://mcp.exemplo.com.br/mcp',
        appPublicUrl: 'https://dev.exemplo.com.br/v2/tenant',
      ),
    );
    final auth = _MockAuthService();
    when(() => auth.currentSession).thenReturn(null);
    getIt.registerSingleton<AuthService>(auth);
  }

  void listaResponde(List<proto.TenantInviteItem> itens) => when(
    () => client.listInvites(any()),
  ).thenAnswer((_) => respostaGrpc(proto.ListInvitesResponse(invites: itens)));

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const InvitesPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  testWidgets('conta sem convite explica o que fazer', (tester) async {
    listaResponde([]);
    registrar();

    await montar(tester);

    expect(find.text('Nenhum convite ainda'), findsOneWidget);
  });

  testWidgets('cada convite mostra o estado em que está', (tester) async {
    // Aceito, revogado e pendente pedem ações diferentes de quem administra;
    // um rótulo só para os três esconderia justamente a diferença.
    listaResponde([
      conviteItemProto(id: 'a', email: 'aceito@x.com', used: true),
      conviteItemProto(id: 'b', email: 'revogado@x.com', revoked: true),
      conviteItemProto(id: 'c', email: 'pendente@x.com'),
    ]);
    registrar();

    await montar(tester);

    expect(find.text('Aceito'), findsOneWidget);
    expect(find.text('Revogado'), findsOneWidget);
    expect(find.text('Pendente'), findsOneWidget);
    // Só o pendente pode ser revogado: os outros dois já terminaram.
    expect(find.byTooltip('Revogar'), findsOneWidget);
  });

  testWidgets('erro do servidor vira tela de erro com nova tentativa', (
    tester,
  ) async {
    when(
      () => client.listInvites(any()),
    ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')));
    registrar();

    await montar(tester);

    expect(find.textContaining('Servidor indisponível'), findsOneWidget);
    expect(find.text('Tentar novamente'), findsOneWidget);
  });

  testWidgets('revogar chama o servidor com o convite certo', (tester) async {
    listaResponde([conviteItemProto(id: 'inv-42')]);
    when(() => client.revokeInvite(any())).thenAnswer(
      (_) => respostaGrpc(proto.RevokeInviteResponse(success: true)),
    );
    registrar();

    await montar(tester);
    await tester.tap(find.byTooltip('Revogar'));
    await tester.pumpAndSettle();

    final enviado =
        verify(() => client.revokeInvite(captureAny())).captured.single
            as proto.RevokeInviteRequest;
    expect(enviado.inviteId, 'inv-42');
  });

  group('novo convite', () {
    Future<void> abrirDialogo(WidgetTester tester) async {
      listaResponde([]);
      registrar();
      await montar(tester);
      await tester.tap(find.text('Novo Convite'));
      await tester.pumpAndSettle();
    }

    testWidgets('oferece o catálogo inteiro de escopos', (tester) async {
      // Eram três escritos à mão: convidar alguém para treinamento,
      // financeiro ou configurações era impossível pela tela.
      await abrirDialogo(tester);

      expect(find.text('Ver atendimentos'), findsOneWidget);
      expect(find.text('Treinar a IA'), findsOneWidget);
      expect(find.text('Ver o financeiro'), findsOneWidget);
      expect(find.text('Alterar as configurações'), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(13));
    });

    testWidgets('sem nome e e-mail não chega ao servidor', (tester) async {
      await abrirDialogo(tester);

      await tester.tap(find.text('Enviar Convite'));
      await tester.pumpAndSettle();

      expect(find.text('Preencha nome e e-mail.'), findsOneWidget);
      verifyNever(() => client.createInvite(any()));
    });

    testWidgets('manda os escopos marcados e os fluxos digitados', (
      tester,
    ) async {
      when(() => client.createInvite(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateInviteResponse(invite: conviteCriadoProto()),
        ),
      );
      await abrirDialogo(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Maria');
      await tester.enterText(find.byType(TextField).at(1), 'maria@x.com');
      await tester.tap(find.text('Ver atendimentos'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '1, 2, x, 3');
      await tester.tap(find.text('Enviar Convite'));
      await tester.pumpAndSettle();

      final enviado =
          verify(() => client.createInvite(captureAny())).captured.single
              as proto.CreateInviteRequest;
      expect(enviado.modulePermissions, ['atendimentos:read']);
      // "x" não é id de fluxo nenhum e é descartado em silêncio — barrar o
      // convite inteiro por uma vírgula sobrando seria pior.
      expect(enviado.flowPermissions, [1, 2, 3]);
    });

    testWidgets('papel Admin não depende das caixas marcadas', (tester) async {
      // Quem deve administrar é convidado pelo papel, e não marcando
      // `tenant:admin` no meio das outras opções — que nem está na lista.
      when(() => client.createInvite(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateInviteResponse(invite: conviteCriadoProto()),
        ),
      );
      await abrirDialogo(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Ana');
      await tester.enterText(find.byType(TextField).at(1), 'ana@x.com');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Admin').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Enviar Convite'));
      await tester.pumpAndSettle();

      final enviado =
          verify(() => client.createInvite(captureAny())).captured.single
              as proto.CreateInviteRequest;
      expect(enviado.role, 'admin');
      expect(enviado.modulePermissions, contains('tenant:admin'));
    });

    testWidgets('convite criado mostra o link absoluto, pronto para copiar', (
      tester,
    ) async {
      // O que a tela mostrava era `/aceitar-convite?token=…`: um caminho.
      // Colado num WhatsApp não abre nada.
      when(() => client.createInvite(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateInviteResponse(
            invite: conviteCriadoProto(token: 'abc123'),
          ),
        ),
      );
      await abrirDialogo(tester);

      await tester.enterText(find.byType(TextField).at(0), 'Maria');
      await tester.enterText(find.byType(TextField).at(1), 'maria@x.com');
      await tester.tap(find.text('Enviar Convite'));
      await tester.pumpAndSettle();

      expect(find.text('Convite criado'), findsOneWidget);
      expect(
        find.text(
          'https://dev.exemplo.com.br/v2/tenant/aceitar-convite?token=abc123',
        ),
        findsOneWidget,
      );
      expect(find.text('Copiar link'), findsOneWidget);
    });

    testWidgets('cancelar não cria nada', (tester) async {
      await abrirDialogo(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => client.createInvite(any()));
    });
  });
}
