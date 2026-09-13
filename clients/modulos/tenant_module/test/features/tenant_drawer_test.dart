import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:login_module/login_module.dart';
import 'package:mocktail/mocktail.dart';
import 'package:tenant_module/src/shared/widgets/tenant_drawer.dart';

class _MockAuthService extends Mock implements AuthService {}

/// O menu é RBAC de UI: as telas administrativas só aparecem para quem tem
/// `tenant:admin`. Defesa em profundidade — o backend já barra por escopo —,
/// mas mostrar o que a pessoa não pode usar é confundir quem opera.
void main() {
  final getIt = GetIt.instance;

  tearDown(() => getIt.reset());

  /// Session de verdade, não mock: `isTenantAdmin` é derivado dos escopos, e
  /// mockar o getter esconderia justamente a regra que se quer exercitar.
  void registrarSessao({bool admin = false, List<String>? escopos}) {
    final auth = _MockAuthService();
    when(() => auth.currentSession).thenReturn(
      Session(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime(2030),
        tenantId: 't-1',
        scopes:
            escopos ??
            (admin ? const ['tenant:admin'] : const ['atendimentos:read']),
        isSuperuser: false,
      ),
    );
    getIt.registerSingleton<AuthService>(auth);
  }

  Future<GoRouter> montar(WidgetTester tester, {String rota = '/'}) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    Widget comDrawer(String titulo) => Scaffold(
      appBar: AppBar(title: Text(titulo)),
      drawer: const TenantDrawer(),
    );

    final router = GoRouter(
      initialLocation: rota,
      routes: [
        GoRoute(path: '/', builder: (_, _) => comDrawer('raiz')),
        GoRoute(
          path: '/atendimentos',
          builder: (_, _) => comDrawer('atendimentos'),
        ),
        GoRoute(path: '/tenant/equipe', builder: (_, _) => comDrawer('equipe')),
        GoRoute(
          path: '/tenant/conexoes',
          builder: (_, _) => comDrawer('conexoes'),
        ),
        GoRoute(
          path: '/tenant/contatos',
          builder: (_, _) => comDrawer('contatos'),
        ),
        GoRoute(path: '/tenant/fluxos', builder: (_, _) => comDrawer('fluxos')),
        GoRoute(
          path: '/tenant/fluxos/:id/etapas',
          builder: (_, _) => comDrawer('etapas'),
        ),
        GoRoute(path: '/tenant/painel', builder: (_, _) => comDrawer('painel')),
        GoRoute(
          path: '/tenant/treinamento',
          builder: (_, _) => comDrawer('treinamento'),
        ),
        GoRoute(
          path: '/tenant/convites',
          builder: (_, _) => comDrawer('convites'),
        ),
        GoRoute(
          path: '/tenant/usuarios',
          builder: (_, _) => comDrawer('usuarios'),
        ),
        GoRoute(path: '/tenant/config', builder: (_, _) => comDrawer('config')),
        GoRoute(path: '/login', builder: (_, _) => comDrawer('login')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('admin do tenant vê as telas administrativas', (tester) async {
    registrarSessao(admin: true);
    await montar(tester);

    expect(find.text('Atendimento (Kanban)'), findsOneWidget);
    expect(find.text('Painel'), findsOneWidget);
    expect(find.text('Contatos'), findsOneWidget);
    expect(find.text('Equipe'), findsOneWidget);
    expect(find.text('Fluxos de atendimento'), findsOneWidget);
    expect(find.text('Conexões de WhatsApp'), findsOneWidget);
    expect(find.text('Treinamento da IA'), findsOneWidget);
    expect(find.text('Convites'), findsOneWidget);
    expect(find.text('Usuários'), findsOneWidget);
    expect(find.text('Configuração do Tenant'), findsOneWidget);
  });

  // B2 — um teste por papel, com os escopos da tabela do plano. Antes o menu
  // era "admin ou nada", e três destes quatro papéis viam só o quadro.
  group('menu por papel', () {
    void confere(Map<String, bool> esperado) {
      esperado.forEach((titulo, visivel) {
        expect(
          find.text(titulo),
          visivel ? findsOneWidget : findsNothing,
          reason: '"$titulo" deveria ${visivel ? '' : 'não '}aparecer',
        );
      });
    }

    testWidgets('manager: operação inteira, sem administração', (tester) async {
      registrarSessao(
        escopos: const [
          'atendimentos:read',
          'atendimentos:write',
          'clientes:read',
          'clientes:write',
          'operacional:read',
          'kanban:admin',
          'treinamento:read',
          'treinamento:write',
          'configuracoes:read',
        ],
      );
      await montar(tester);

      confere({
        'Painel': true,
        'Contatos': true,
        'Equipe': true,
        'Fluxos de atendimento': true,
        'Campos do atendimento': true,
        'Conexões de WhatsApp': true,
        'Treinamento da IA': true,
        'Configuração do Tenant': true,
        'Convites': false,
        'Usuários': false,
      });
    });

    testWidgets('staff: o que o atendimento usa', (tester) async {
      // Os escopos que um convite de atendente recebe por padrão.
      registrarSessao(
        escopos: const [
          'atendimentos:read',
          'atendimentos:write',
          'clientes:write',
        ],
      );
      await montar(tester);

      confere({
        'Atendimento (Kanban)': true,
        'Aplicativos conectados': true,
        'Painel': true,
        'Contatos': true,
        'Fluxos de atendimento': true,
        'Equipe': false,
        'Campos do atendimento': false,
        'Conexões de WhatsApp': false,
        'Treinamento da IA': false,
        'Convites': false,
        'Usuários': false,
        'Configuração do Tenant': false,
      });
    });

    testWidgets('viewer: só as telas de leitura do atendimento', (
      tester,
    ) async {
      registrarSessao(escopos: const ['atendimentos:read']);
      await montar(tester);

      confere({
        'Atendimento (Kanban)': true,
        'Aplicativos conectados': true,
        'Painel': true,
        'Fluxos de atendimento': true,
        'Equipe': false,
        'Conexões de WhatsApp': false,
        'Treinamento da IA': false,
        'Convites': false,
        'Usuários': false,
      });
    });

    testWidgets('sem sessão: só o quadro e os aplicativos', (tester) async {
      final auth = _MockAuthService();
      when(() => auth.currentSession).thenReturn(null);
      getIt.registerSingleton<AuthService>(auth);
      await montar(tester);

      confere({
        'Atendimento (Kanban)': true,
        'Painel': false,
        'Contatos': false,
        'Convites': false,
      });
    });
  });

  testWidgets('o menu rola quando a janela é baixa', (tester) async {
    // O menu passou de oito itens: numa janela baixa a Column rígida estourava
    // e escondia o fim da lista sem sinalizar que havia mais.
    registrarSessao(admin: true);
    tester.view.physicalSize = const Size(1200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            appBar: AppBar(title: const Text('raiz')),
            drawer: const TenantDrawer(),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    // Sair fica fora da rolagem: é o item que não pode sumir.
    expect(find.text('Sair'), findsOneWidget);
  });

  testWidgets('navega para a equipe e fecha o menu', (tester) async {
    registrarSessao(admin: true);
    final router = await montar(tester);

    await tester.tap(find.text('Equipe'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/tenant/equipe',
    );
    // O menu fecha ao navegar: deixá-lo aberto sobre a tela nova esconderia o
    // que a pessoa acabou de pedir.
    expect(find.text('Convites'), findsNothing);
  });

  testWidgets('navega para as conexões', (tester) async {
    registrarSessao(admin: true);
    final router = await montar(tester);

    await tester.tap(find.text('Conexões de WhatsApp'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/tenant/conexoes',
    );
  });

  testWidgets('navega para os contatos', (tester) async {
    registrarSessao(admin: true);
    final router = await montar(tester);

    await tester.tap(find.text('Contatos'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/tenant/contatos',
    );
  });

  testWidgets('navega para o treinamento', (tester) async {
    registrarSessao(admin: true);
    final router = await montar(tester);

    await tester.tap(find.text('Treinamento da IA'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
      '/tenant/treinamento',
    );
  });

  testWidgets('a subtela mantém a seção marcada no menu', (tester) async {
    // Em `/tenant/fluxos/3/etapas` a pessoa ainda está em Fluxos; deixar o
    // menu sem marca nenhuma faria parecer que ela saiu da seção.
    registrarSessao(admin: true);
    await montar(tester, rota: '/tenant/fluxos/3/etapas');

    final marcado = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected)
        .toList();
    expect(marcado, hasLength(1));
    expect((marcado.single.title! as Text).data, 'Fluxos de atendimento');
  });

  testWidgets('o item da rota atual fica marcado', (tester) async {
    registrarSessao(admin: true);
    await montar(tester, rota: '/tenant/equipe');

    final marcado = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected);
    expect(marcado, hasLength(1));
  });
}
