import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_controller.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/chat_page.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/kanban_page.dart';

import '../../support/fake_gateway.dart';

/// O quadro de atendimento é a primeira tela depois do login. Os dois defeitos
/// que estes testes travam foram vistos em uso: um quadro que abre em branco
/// numa conta nova, e uma tela sem menu, de onde não se chega a configuração
/// nenhuma.
void main() {
  conversaAoLadoDoQuadro();
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

    expect(find.text('ENTRADA'), findsOneWidget);
    expect(find.text('TRABALHANDO'), findsOneWidget);
    expect(find.text('FECHADO'), findsOneWidget);
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

    await montar(tester, drawer: const Drawer(child: Text('menu do tenant')));

    expect(find.byTooltip('Open navigation menu'), findsOneWidget);
  });

  testWidgets('sem menu fornecido, a tela funciona igual', (tester) async {
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.text('ENTRADA'), findsOneWidget);
  });

  testWidgets('a conversa aparece na coluna em que está', (tester) async {
    final gateway =
        FakeAtendimentoGateway(
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
    final gateway =
        FakeAtendimentoGateway(
            fila: [atendimentoDeTeste(id: 7, etapaAtualId: 999)],
          )
          ..colunas = colunasDeTeste()
          ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    expect(find.text('SEM COLUNA'), findsOneWidget);
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
    final gateway =
        FakeAtendimentoGateway(
            fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
          )
          ..colunas = colunasDeTeste()
          ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    // O menu do cartão abre no botão direito: o clique comum abre a conversa.
    await tester.tap(find.text('Assunto 1'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();

    // O atendimento de teste nasce em 'fila'.
    expect(find.text('Devolver à fila'), findsNothing);
    expect(find.text('Assumir'), findsOneWidget);
    expect(find.text('Resolver'), findsOneWidget);
  });

  testWidgets('escolher um estado manda ao servidor', (tester) async {
    final gateway =
        FakeAtendimentoGateway(
            fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
          )
          ..colunas = colunasDeTeste()
          ..fluxos = fluxosDeTeste();
    registrar(gateway);

    await montar(tester);

    await tester.tap(find.text('Assunto 1'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resolver'));
    await tester.pumpAndSettle();

    expect(gateway.statusRecebido, 'resolvido');
  });
}

/// A conversa ao lado do quadro.
///
/// Era só página cheia: clicar num cartão empurrava outra tela por cima, e o
/// operador perdia de vista a fila que estava trabalhando. Na v1 a conversa
/// abria à direita, sem sair do quadro — é o que estes testes fixam.
void conversaAoLadoDoQuadro() {
  final getIt = GetIt.instance;

  tearDown(() => getIt.reset());

  void registrarTudo(FakeAtendimentoGateway gateway) {
    final u = usecasesSobre(gateway);
    getIt
      ..registerSingleton<KanbanController>(
        KanbanController(
          listUsecase: u.list,
          moveUsecase: u.move,
          fluxosUsecase: u.fluxos,
          colunasUsecase: u.colunas,
          statusUsecase: u.status,
        ),
      )
      ..registerSingleton<GetThreadUsecase>(u.thread)
      ..registerSingleton<SendOutboundMessageUsecase>(u.send)
      ..registerSingleton<AtendimentoEventoStream>(u.eventos)
      ..registerSingleton<GetFichaUsecase>(u.ficha)
      ..registerSingleton<CriarEtiquetaUsecase>(u.criarEtiqueta)
      ..registerSingleton<AlternarEtiquetaUsecase>(u.alternarEtiqueta)
      ..registerSingleton<CriarNotaUsecase>(u.criarNota)
      ..registerSingleton<DefinirBotDaConversaUsecase>(u.definirBot)
      ..registerSingleton<DefinirValorCampoUsecase>(u.definirValorCampo);
  }

  Future<void> abrirOQuadro(
    WidgetTester tester, {
    required double largura,
  }) async {
    final gateway = FakeAtendimentoGateway()
      ..colunas = colunasDeTeste()
      ..fluxos = fluxosDeTeste()
      ..fila = [atendimentoDeTeste(id: 7, etapaAtualId: 1)];
    registrarTudo(gateway);

    tester.view.physicalSize = Size(largura, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: KanbanPage()));
    await tester.pumpAndSettle();
  }

  testWidgets('em janela larga a conversa abre ao lado, sem sair do quadro', (
    tester,
  ) async {
    await abrirOQuadro(tester, largura: 1600);

    // O quadro está lá antes de clicar, e a conversa não.
    expect(find.text('ENTRADA'), findsOneWidget);
    expect(find.byType(PainelDeConversa), findsNothing);

    // O quadro divide a tela com a conversa: a coluna do cartão pode estar
    // fora da vista, e quem usa rola até ela.
    await tester.ensureVisible(find.text('Assunto 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assunto 7'));
    await tester.pumpAndSettle();

    expect(find.byType(PainelDeConversa), findsOneWidget);
    expect(
      find.text('ENTRADA'),
      findsOneWidget,
      reason: 'o quadro sumiu: a conversa tomou a tela em vez de dividir',
    );
  });

  testWidgets('fechar a conversa devolve o quadro inteiro', (tester) async {
    await abrirOQuadro(tester, largura: 1600);
    await tester.ensureVisible(find.text('Assunto 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assunto 7'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Fechar a conversa'));
    await tester.pumpAndSettle();

    expect(find.byType(PainelDeConversa), findsNothing);
    expect(find.text('ENTRADA'), findsOneWidget);
  });

  testWidgets('em janela estreita continua sendo tela cheia', (tester) async {
    // Espremer quadro e conversa numa janela pequena deixa os dois ilegíveis,
    // que é pior que escolher um.
    await abrirOQuadro(tester, largura: 800);

    // Numa janela de 800px a coluna do cartão fica fora da vista: o quadro
    // rola na horizontal. Sem isto o toque cairia no vazio e o teste passaria
    // por não ter acontecido nada.
    await tester.ensureVisible(find.text('Assunto 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assunto 7'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatPage), findsOneWidget);
    // O botão de fechar só existe no painel embutido; como tela cheia quem
    // volta é a `AppBar`. É ele que distingue os dois modos.
    expect(
      find.byTooltip('Fechar a conversa'),
      findsNothing,
      reason: 'abriu como painel embutido numa janela que não comporta os dois',
    );
  });
}
