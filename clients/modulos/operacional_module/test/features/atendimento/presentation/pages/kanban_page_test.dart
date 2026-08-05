import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/kanban_page.dart';

import '../../support/fake_gateway.dart';

/// O quadro de atendimento é a primeira tela depois do login. Os dois defeitos
/// que estes testes travam foram vistos em uso: um quadro que abre em branco
/// numa conta nova, e uma tela sem menu, de onde não se chega a configuração
/// nenhuma.
void main() {
  final getIt = GetIt.instance;

  tearDown(() => getIt.reset());

  KanbanController registrar(FakeAtendimentoGateway gateway) {
    final u = usecasesSobre(gateway);
    final controller = KanbanController(
      listUsecase: u.list,
      moveUsecase: u.move,
      fluxosUsecase: u.fluxos,
      colunasUsecase: u.colunas,
      statusUsecase: u.status,
    );
    getIt.registerSingleton<KanbanController>(controller);
    return controller;
  }

  Future<void> montar(WidgetTester tester, {Widget? drawer}) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(MaterialApp(home: KanbanPage(drawer: drawer)));
    await tester.pumpAndSettle();
  }

  testWidgets('as colunas do fluxo aparecem mesmo sem conversa nenhuma', (
    tester,
  ) async {
    // O quadro vazio de uma conta nova mostrava "nenhum atendimento na fila" e
    // nada mais — não havia sequer para onde arrastar quando a primeira
    // conversa chegasse.
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.text('Entrada'), findsOneWidget);
    expect(find.text('Trabalhando'), findsOneWidget);
    expect(find.text('Fechado'), findsOneWidget);
  });

  testWidgets('sem fluxo cadastrado, convida a criar um', (tester) async {
    // "Aguarde chegar conversa" seria mentira: sem quadro, nada chega a lugar
    // nenhum.
    final gateway = FakeAtendimentoGateway()
      ..colunas = const []
      ..fluxos = const [];
    registrar(gateway);

    await montar(tester);

    expect(find.text('Nenhum quadro configurado'), findsOneWidget);
    expect(find.textContaining('Fluxos de atendimento'), findsOneWidget);
  });

  testWidgets('o menu do app aparece quando é fornecido', (tester) async {
    // Sem ele, quem entrava caía numa fila vazia sem caminho para nenhuma
    // configuração.
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(
      tester,
      drawer: const Drawer(child: Text('menu do tenant')),
    );

    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
  });

  testWidgets('sem menu fornecido, a tela funciona igual', (tester) async {
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.text('Entrada'), findsOneWidget);
  });

  testWidgets('a conversa aparece na coluna em que está', (tester) async {
    final gateway = FakeAtendimentoGateway(
      fila: [atendimentoDeTeste(id: 1, etapaAtualId: 20)],
    )
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.textContaining('Assunto 1'), findsOneWidget);
  });

  testWidgets('conversa fora das colunas conhecidas ganha lugar próprio', (
    tester,
  ) async {
    // Chegou antes de o fluxo existir, ou aponta para coluna já removida.
    // Escondê-la faria sumir atendimento de verdade.
    final gateway = FakeAtendimentoGateway(
      fila: [atendimentoDeTeste(id: 7, etapaAtualId: 999)],
    )
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.text('Sem coluna'), findsOneWidget);
    expect(find.textContaining('Assunto 7'), findsOneWidget);
  });

  testWidgets('o seletor de quadro só aparece com mais de um', (tester) async {
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.byType(DropdownButton<int>), findsNothing);
  });

  testWidgets('com dois quadros, dá para trocar', (tester) async {
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = const [
        FluxoDoQuadroDeTeste.suporte,
        FluxoDoQuadroDeTeste.comercial,
      ];
    registrar(gateway);

    await montar(tester);

    expect(find.byType(DropdownButton<int>), findsOneWidget);
    expect(find.text('Suporte · Padrão'), findsOneWidget);
  });

  testWidgets('o menu de estado não oferece o estado atual', (tester) async {
    // Oferecer "assumir" para quem já está atendendo seria um clique que não
    // muda nada.
    final gateway = FakeAtendimentoGateway(
      fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
    )
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    await tester.tap(find.byTooltip('Mudar o estado'));
    await tester.pumpAndSettle();

    // O atendimento de teste nasce em 'fila'.
    expect(find.text('Devolver à fila'), findsNothing);
    expect(find.text('Assumir'), findsOneWidget);
    expect(find.text('Resolver'), findsOneWidget);
  });

  testWidgets('escolher um estado manda ao servidor', (tester) async {
    final gateway = FakeAtendimentoGateway(
      fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
    )
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    await tester.tap(find.byTooltip('Mudar o estado'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolver'));
    await tester.pumpAndSettle();

    expect(gateway.statusRecebido, 'resolvido');
  });
}
