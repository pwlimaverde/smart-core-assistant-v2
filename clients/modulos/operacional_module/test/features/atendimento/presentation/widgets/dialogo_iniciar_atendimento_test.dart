import 'package:api_client/api_client.dart' show GrpcError;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/contato_para_atendimento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/quadro.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_state.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/dialogo_iniciar_atendimento.dart';

import '../../support/fake_gateway.dart';

/// C3 — abrir conversa a partir de um cliente cadastrado.
void main() {
  final getIt = GetIt.instance;
  late FakeAtendimentoGateway gateway;

  const colunas = [
    ColunaDoQuadro(
      id: 10,
      nome: 'Entrada',
      cor: '#888',
      ordem: 0,
      tipo: 'fila',
    ),
    ColunaDoQuadro(
      id: 11,
      nome: 'Em atendimento',
      cor: '#888',
      ordem: 1,
      tipo: 'trabalho',
    ),
  ];

  setUp(() {
    gateway = FakeAtendimentoGateway();
    getIt.registerSingleton<IniciarAtendimentoUsecase>(
      usecasesSobre(gateway).iniciar,
    );
  });
  tearDown(() => getIt.reset());

  /// Busca controlável: o diálogo recebe a função por injeção porque cadastro
  /// de contato é do `tenant_module`, e o operacional não o conhece.
  Future<List<ContatoParaAtendimento>> buscaCom(
    List<ContatoParaAtendimento> achados,
  ) async => achados;

  Future<int?> montar(
    WidgetTester tester, {
    required BuscarContatos buscar,
    List<ColunaDoQuadro> comColunas = colunas,
  }) async {
    tester.view.physicalSize = const Size(900, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    int? resultado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                resultado = await mostrarDialogoIniciarAtendimento(
                  context,
                  quadro: KanbanViewModel(
                    fluxoId: 1,
                    fluxos: const [FluxoDoQuadroDeTeste.suporte],
                    colunas: comColunas,
                    porEtapa: const {},
                  ),
                  buscarContatos: buscar,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return resultado;
  }

  Future<void> escolher(WidgetTester tester, String termo) async {
    await tester.enterText(find.byType(TextField).first, termo);
    // A busca só sai depois da pausa: sem ela, digitar cinco letras seriam
    // cinco consultas, quatro delas para prefixos que ninguém queria ver.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  testWidgets('só habilita abrir depois de escolher o cliente', (tester) async {
    await montar(
      tester,
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 5, nome: 'Maria', telefone: '5511999998888'),
      ]),
    );

    final botao = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Abrir conversa'),
    );
    expect(botao.onPressed, isNull, reason: 'sem cliente não há o que abrir');

    await escolher(tester, 'maria');
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();

    final depois = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Abrir conversa'),
    );
    expect(depois.onPressed, isNotNull);
  });

  testWidgets('a primeira coluna do quadro já vem escolhida', (tester) async {
    // É a fila de entrada. Deixar em branco faria o operador decidir toda vez
    // algo que quase sempre é o mesmo.
    await montar(tester, buscar: (_) => buscaCom(const []));

    expect(find.text('Entrada'), findsOneWidget);
  });

  testWidgets('busca curta demais nem chega ao servidor', (tester) async {
    var chamadas = 0;
    await montar(
      tester,
      buscar: (_) async {
        chamadas++;
        return const [];
      },
    );

    await escolher(tester, 'm');
    expect(chamadas, 0);

    await escolher(tester, 'ma');
    expect(chamadas, 1);
  });

  testWidgets('falha da busca não derruba o diálogo', (tester) async {
    // A busca é auxiliar: um erro no meio da lista atrapalharia mais do que
    // ajudaria — a lista fica vazia e a pessoa digita de novo.
    await montar(tester, buscar: (_) async => throw Exception('rede'));

    await escolher(tester, 'maria');

    expect(find.text('Iniciar atendimento'), findsOneWidget);
  });

  testWidgets('abre a conversa e devolve o id', (tester) async {
    gateway.atendimentoIniciadoId = 321;
    await montar(
      tester,
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 5, nome: 'Maria', telefone: '5511999998888'),
      ]),
    );

    await escolher(tester, 'maria');
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'renovação');
    await tester.tap(find.text('Abrir conversa'));
    await tester.pumpAndSettle();

    expect(gateway.chamadasIniciar, 1);
    expect(gateway.iniciarRecebido?.contatoId, 5);
    expect(gateway.iniciarRecebido?.assunto, 'renovação');
    // A etapa vai junto: um atendimento sem etapa não aparece em coluna
    // nenhuma do quadro, e nascer invisível é o pior desfecho.
    expect(gateway.iniciarRecebido?.etapaInicialId, 10);
  });

  testWidgets('conversa que já existia abre avisando, não como nova', (
    tester,
  ) async {
    // Anunciar "atendimento criado" para uma que já estava aberta mandaria o
    // operador procurar um cartão novo que não existe.
    gateway.iniciarJaExistia = true;
    await montar(
      tester,
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 5, nome: 'Maria', telefone: '5511999998888'),
      ]),
    );

    await escolher(tester, 'maria');
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir conversa'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('já tinha uma conversa aberta'), findsOneWidget);
  });

  testWidgets('erro do servidor fica dentro da janela', (tester) async {
    // Fechar a janela e piscar um aviso atrás faria a pessoa perder o que
    // preencheu.
    gateway.erroIniciar = GrpcError.failedPrecondition('limite diário');
    await montar(
      tester,
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 5, nome: 'Maria', telefone: '5511999998888'),
      ]),
    );

    await escolher(tester, 'maria');
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abrir conversa'));
    await tester.pumpAndSettle();

    expect(find.text('Iniciar atendimento'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('sem coluna no quadro não há como abrir', (tester) async {
    // Um quadro sem etapa não tem onde pôr a conversa.
    await montar(
      tester,
      comColunas: const [],
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 5, nome: 'Maria', telefone: '5511999998888'),
      ]),
    );

    await escolher(tester, 'maria');
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();

    final botao = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Abrir conversa'),
    );
    expect(botao.onPressed, isNull);
  });

  testWidgets('contato sem nome aparece pelo telefone', (tester) async {
    await montar(
      tester,
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 9, nome: '', telefone: '5511777776666'),
      ]),
    );

    await escolher(tester, '5511');

    expect(find.text('5511777776666'), findsWidgets);
  });

  testWidgets('trocar de cliente volta para a busca', (tester) async {
    await montar(
      tester,
      buscar: (_) => buscaCom(const [
        ContatoParaAtendimento(id: 5, nome: 'Maria', telefone: '5511999998888'),
      ]),
    );

    await escolher(tester, 'maria');
    await tester.tap(find.text('Maria').last);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Escolher outro cliente'), findsOneWidget);

    await tester.tap(find.byTooltip('Escolher outro cliente'));
    await tester.pumpAndSettle();

    final botao = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Abrir conversa'),
    );
    expect(botao.onPressed, isNull);
  });

  testWidgets('cancelar não chama o servidor', (tester) async {
    await montar(tester, buscar: (_) => buscaCom(const []));

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(gateway.chamadasIniciar, 0);
    expect(find.byType(AlertDialog), findsNothing);
  });
}
