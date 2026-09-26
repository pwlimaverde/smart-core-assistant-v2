import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/chat_page.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/kanban_page.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/avatar_do_contato.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/mini_barra_da_conversa.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/painel_ficha.dart';

import '../../support/fake_gateway.dart';

/// O workspace: um clique no cartão abre a conversa com as informações do
/// atendimento à direita, clicar fora recolhe a conversa para a mini-barra, e
/// os modos de foco (Kanban / Dividido / Atendimento) com os atalhos
/// Alt+1/2/3, Esc e `i`.
void main() {
  final getIt = GetIt.instance;

  setUp(KanbanPage.reiniciarModoDeFoco);
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

  late FakeAtendimentoGateway gatewayAtual;

  Future<void> abrirOQuadro(
    WidgetTester tester, {
    double largura = 1600,
  }) async {
    final gateway = gatewayAtual = FakeAtendimentoGateway()
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

  Future<void> abrirACoversa(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Assunto 7'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Assunto 7'));
    await tester.pumpAndSettle();
  }

  testWidgets('um clique no cartão abre a conversa e as informações', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    expect(find.byType(PainelDeConversa), findsOneWidget);
    expect(
      find.byType(PainelFicha),
      findsOneWidget,
      reason: 'o cartão abriu a conversa, mas não as informações ao lado',
    );
    // Sem botão de detalhes no cartão: o cartão é o caminho.
    expect(find.byTooltip('Detalhes do atendimento'), findsNothing);
    // As informações ficam AO LADO da conversa, não por cima.
    final conversa = tester.getRect(
      find.widgetWithText(TextField, 'Digite uma mensagem…'),
    );
    final ficha = tester.getRect(find.byType(PainelFicha));
    expect(ficha.left, greaterThanOrEqualTo(conversa.right));
  });

  testWidgets('o botão de informações do painel fecha e reabre a ficha', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);
    expect(find.byType(PainelFicha), findsOneWidget);

    await tester.tap(find.byTooltip('Detalhes do atendimento (i)'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsNothing);
    expect(find.byType(PainelDeConversa), findsOneWidget);

    await tester.tap(find.byTooltip('Detalhes do atendimento (i)'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsOneWidget);
  });

  testWidgets('as informações mostram e mudam o estado do atendimento', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    expect(find.text('ATENDIMENTO'), findsOneWidget);
    expect(find.text('Na fila'), findsOneWidget);

    await tester.tap(find.byTooltip('Mudar o status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pendente').last);
    await tester.pumpAndSettle();
    expect(gatewayAtual.statusRecebido, 'pendencia');
  });

  testWidgets('a faixa de ações rápidas resolve a conversa', (tester) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    await tester.tap(find.text('Resolver'));
    await tester.pumpAndSettle();
    expect(gatewayAtual.statusRecebido, 'resolvido');
  });

  testWidgets('a nota interna vai para a ficha, não para o contato', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    await tester.tap(find.text('Nota interna'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nota interna — só a equipe vê'),
      'cliente prefere ligação',
    );
    await tester.tap(find.byTooltip('Salvar nota interna'));
    await tester.pumpAndSettle();

    expect(gatewayAtual.notaRecebida, 'cliente prefere ligação');
    expect(gatewayAtual.chamadasSend, 0);
  });

  testWidgets('clicar no quadro fora do cartão recolhe a conversa', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    // O título da coluna não tem ação própria: é "fora" da conversa.
    await tester.tap(find.text('ENTRADA'));
    await tester.pumpAndSettle();

    expect(find.byType(PainelDeConversa), findsNothing);
    expect(find.byType(MiniBarraDaConversa), findsOneWidget);

    await tester.tap(find.text('Abrir conversa'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelDeConversa), findsOneWidget);
    expect(find.byType(MiniBarraDaConversa), findsNothing);
  });

  testWidgets('a mini-barra abre os detalhes e fecha a conversa', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);
    await tester.tap(find.byTooltip('Minimizar (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byType(MiniBarraDaConversa), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(MiniBarraDaConversa),
        matching: find.byTooltip('Detalhes do atendimento'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsOneWidget);

    await tester.tap(find.byTooltip('Minimizar (Esc)'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(MiniBarraDaConversa),
        matching: find.byTooltip('Fechar a conversa'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MiniBarraDaConversa), findsNothing);
    expect(find.byType(PainelDeConversa), findsNothing);
  });

  testWidgets('Esc reduz o foco aos poucos e i alterna os detalhes', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);
    expect(find.byType(PainelFicha), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsOneWidget);

    // Primeiro Esc fecha os detalhes; o segundo recolhe a conversa.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsNothing);
    expect(find.byType(PainelDeConversa), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(MiniBarraDaConversa), findsOneWidget);
  });

  testWidgets('os modos de foco trocam pelo seletor e por Alt+1/2/3', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    // Atendimento: a conversa ocupa a tela, e o quadro sai.
    await tester.tap(find.byTooltip('Atendimento (Alt+3)'));
    await tester.pumpAndSettle();
    expect(find.text('ENTRADA'), findsNothing);
    expect(find.byType(PainelDeConversa), findsOneWidget);
    // O quadro virou a trilha: o cartão continua a um clique.
    expect(find.byType(AvatarDoContato), findsWidgets);

    // Esc fecha as informações; o seguinte volta ao dividido.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('ENTRADA'), findsOneWidget);
    expect(find.byType(PainelDeConversa), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(MiniBarraDaConversa), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();
    expect(find.byType(PainelDeConversa), findsOneWidget);

    await tester.tap(find.byTooltip('Expandir (Alt+3)'));
    await tester.pumpAndSettle();
    expect(find.text('ENTRADA'), findsNothing);
  });

  testWidgets('em tela cheia (janela estreita) a ficha abre pela barra', (
    tester,
  ) async {
    await abrirOQuadro(tester, largura: 700);
    await tester.ensureVisible(find.text('Assunto 7'));
    await tester.pumpAndSettle();
    await abrirACoversa(tester);
    expect(find.byType(ChatPage), findsOneWidget);
    expect(find.byType(PainelFicha), findsNothing);

    await tester.tap(find.byTooltip('Detalhes do atendimento'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsOneWidget);
  });
}
