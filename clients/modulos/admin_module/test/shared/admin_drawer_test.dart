import 'package:admin_module/src/shared/widgets/admin_drawer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// O menu lateral do painel: a navegação inteira do superusuário passa por ele.
///
/// Lê `matchedLocation` do GoRouter para marcar o item ativo, então o teste monta
/// um roteador real com as oito rotas e verifica o destaque e a navegação.
void main() {
  const rotas = [
    '/admin/dashboard',
    '/admin/core-settings',
    '/admin/tenant-config',
    '/admin/tenants',
    '/admin/billing',
    '/admin/evolution',
    '/admin/feature-flags',
    '/admin/audit',
    '/login',
  ];

  Future<GoRouter> montar(WidgetTester tester, String rota) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final router = GoRouter(
      initialLocation: rota,
      routes: [
        for (final path in rotas)
          GoRoute(
            path: path,
            builder: (_, _) =>
                const Scaffold(drawer: AdminDrawer(), body: SizedBox.shrink()),
          ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('lista todos os destinos do painel', (tester) async {
    await montar(tester, '/admin/dashboard');

    for (final rotulo in const [
      'Dashboard Geral',
      'Configurações Globais',
      'Configurações de Tenant',
      'Clientes / Tenants',
      'Planos & Faturamento',
      'Integração Evolution',
      'Feature Flags',
      'Auditoria & Segurança',
    ]) {
      expect(
        find.text(rotulo),
        findsOneWidget,
        reason: 'o destino "$rotulo" precisa aparecer no menu',
      );
    }
  });

  testWidgets('marca exatamente o item da rota atual', (tester) async {
    await montar(tester, '/admin/tenants');

    final selecionados = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected)
        .toList();

    expect(selecionados, hasLength(1));
    expect((selecionados.single.title! as Text).data, 'Clientes / Tenants');
  });

  testWidgets('em outra rota, o destaque acompanha', (tester) async {
    await montar(tester, '/admin/audit');

    final selecionado = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .firstWhere((t) => t.selected);

    expect((selecionado.title! as Text).data, 'Auditoria & Segurança');
  });

  testWidgets('tocar num destino navega para a rota correspondente', (
    tester,
  ) async {
    final router = await montar(tester, '/admin/dashboard');

    await tester.tap(find.text('Planos & Faturamento'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/admin/billing',
    );
  });

  testWidgets('nenhum item fica marcado numa rota fora do painel', (
    tester,
  ) async {
    await montar(tester, '/login');

    final selecionados = tester
        .widgetList<ListTile>(find.byType(ListTile))
        .where((t) => t.selected);

    expect(selecionados, isEmpty);
  });
}
