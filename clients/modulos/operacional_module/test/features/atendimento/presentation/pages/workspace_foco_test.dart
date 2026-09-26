import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/chat_page.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/kanban_page.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/mini_barra_da_conversa.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/painel_ficha.dart';

import '../../support/fake_gateway.dart';

/// O workspace da v1: o cartão abre os detalhes, clicar fora recolhe a
/// conversa para a mini-barra, e os modos de foco (Kanban / Dividido /
/// Atendimento) com os atalhos Alt+1/2/3, Esc e `i`.
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

  Future<void> abrirOQuadro(
    WidgetTester tester, {
    double largura = 1600,
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

  Future<void> abrirACoversa(WidgetTester tester) async {
    await tester.tap(find.text('Assunto 7'));
    await tester.pumpAndSettle();
  }

  testWidgets('o botão de detalhes do cartão abre a conversa com a ficha', (
    tester,
  ) async {
    await abrirOQuadro(tester);

    await tester.tap(find.byTooltip('Detalhes do atendimento'));
    await tester.pumpAndSettle();

    expect(find.byType(PainelDeConversa), findsOneWidget);
    expect(
      find.byType(PainelFicha),
      findsOneWidget,
      reason: 'o cartão abriu, mas os detalhes (e os campos) não',
    );
    expect(find.text('Detalhes do atendimento'), findsOneWidget);
  });

  testWidgets('o botão de detalhes do painel abre e fecha a ficha', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);
    expect(find.byType(PainelFicha), findsNothing);

    await tester.tap(find.byTooltip('Detalhes do atendimento (i)'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsOneWidget);

    await tester.tap(find.byTooltip('Fechar os detalhes (Esc)'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsNothing);
    expect(find.byType(PainelDeConversa), findsOneWidget);
  });

  testWidgets('clicar no quadro fora do cartão recolhe a conversa', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

    // O título da coluna não tem ação própria: é "fora" da conversa.
    await tester.tap(find.text('Entrada'));
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

  testWidgets('Esc reduz o foco aos poucos e i abre os detalhes', (
    tester,
  ) async {
    await abrirOQuadro(tester);
    await abrirACoversa(tester);

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
    await tester.tap(
      find.descendant(
        of: find.byType(SegmentedButton<ModoDeFoco>),
        matching: find.text('Atendimento'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Entrada'), findsNothing);
    expect(find.byType(PainelDeConversa), findsOneWidget);

    // Esc volta ao dividido.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('Entrada'), findsOneWidget);
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
    expect(find.text('Entrada'), findsNothing);
  });

  testWidgets('em tela cheia (janela estreita) a ficha abre pela barra', (
    tester,
  ) async {
    await abrirOQuadro(tester, largura: 800);
    await tester.ensureVisible(find.text('Assunto 7'));
    await tester.pumpAndSettle();
    await abrirACoversa(tester);
    expect(find.byType(ChatPage), findsOneWidget);

    await tester.tap(find.byTooltip('Detalhes do atendimento'));
    await tester.pumpAndSettle();
    expect(find.byType(PainelFicha), findsOneWidget);
  });
}
