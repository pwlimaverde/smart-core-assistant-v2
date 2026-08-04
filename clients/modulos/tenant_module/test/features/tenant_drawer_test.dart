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
  void registrarSessao({required bool admin}) {
    final auth = _MockAuthService();
    when(() => auth.currentSession).thenReturn(
      Session(
        accessToken: 'a',
        refreshToken: 'r',
        expiresAt: DateTime(2030),
        tenantId: 't-1',
        scopes: admin ? const ['tenant:admin'] : const ['atendimentos:read'],
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
    expect(find.text('Equipe'), findsOneWidget);
    expect(find.text('Conexões de WhatsApp'), findsOneWidget);
    expect(find.text('Treinamento da IA'), findsOneWidget);
    expect(find.text('Convites'), findsOneWidget);
  });

  testWidgets('sem tenant:admin, só o workspace aparece', (tester) async {
    registrarSessao(admin: false);
    await montar(tester);

    expect(find.text('Atendimento (Kanban)'), findsOneWidget);
    expect(find.text('Equipe'), findsNothing);
    expect(find.text('Conexões de WhatsApp'), findsNothing);
    expect(find.text('Treinamento da IA'), findsNothing);
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

  testWidgets('o item da rota atual fica marcado', (tester) async {
    registrarSessao(admin: true);
    await montar(tester, rota: '/tenant/equipe');

    final marcado = tester.widgetList<ListTile>(find.byType(ListTile)).where(
          (t) => t.selected,
        );
    expect(marcado, hasLength(1));
  });
}
