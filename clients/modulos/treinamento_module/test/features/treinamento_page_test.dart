import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treinamento_module/src/features/treinamento/data/datasources/treinamento_datasources.dart';
import 'package:treinamento_module/src/features/treinamento/data/repositories/treinamento_repositories.dart';
import 'package:treinamento_module/src/features/treinamento/domain/usecases/treinamento_usecases.dart';
import 'package:treinamento_module/src/features/treinamento/presentation/controllers/treinamento_controllers.dart';
import 'package:treinamento_module/src/features/treinamento/presentation/pages/treinamento_page.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  atualizaSozinhaEnquantoProcessa();
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyTreinamentosRequest());
    registerFallbackValue(proto.CreateMyTreinamentoRequest());
    registerFallbackValue(proto.FinalizarMyTreinamentoRequest());
    registerFallbackValue(proto.RemoverMyTreinamentoRequest());
  });

  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  void registrar() {
    getIt.registerSingleton<TreinamentoController>(
      TreinamentoController(
        listar: ListarTreinamentosUsecase(
          repository: ListarTreinamentosRepository(
            datasource: ListarTreinamentosDatasource(client: client),
          ),
        ),
        criar: CriarTreinamentoUsecase(
          repository: CriarTreinamentoRepository(
            datasource: CriarTreinamentoDatasource(client: client),
          ),
        ),
        finalizar: FinalizarTreinamentoUsecase(
          repository: FinalizarTreinamentoRepository(
            datasource: FinalizarTreinamentoDatasource(client: client),
          ),
        ),
        remover: RemoverTreinamentoUsecase(
          repository: RemoverTreinamentoRepository(
            datasource: RemoverTreinamentoDatasource(client: client),
          ),
        ),
      ),
    );
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: '/',
      routes: [GoRoute(path: '/', builder: (_, _) => const TreinamentoPage())],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  void respondeCom({bool finalizado = false, bool vetorizado = false}) {
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.ListMyTreinamentosResponse(
          treinamentos: [
            proto.MyTreinamento(
              id: 1,
              tag: 'horario',
              grupo: 'atendimento',
              conteudo: 'Abrimos de segunda a sexta.',
              finalizado: finalizado,
              vetorizado: vetorizado,
              criadoEm: Int64(DateTime(2026, 8, 1).millisecondsSinceEpoch),
              atualizadoEm: Int64(DateTime(2026, 8, 2).millisecondsSinceEpoch),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('lista o material com a situação', (tester) async {
    respondeCom(finalizado: true, vetorizado: true);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('horario'), findsOneWidget);
    expect(find.text('Ativo'), findsOneWidget);
  });

  testWidgets('material já vetorizado não oferece revisão', (tester) async {
    // Revisar o que a IA já processou pediria retrabalho sem ganho: o texto
    // em uso é aquele. Reprocessar é o caminho, não revisar de novo.
    respondeCom(finalizado: true, vetorizado: true);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Revisar e enviar para a IA'), findsNothing);
    expect(find.byTooltip('Remover'), findsOneWidget);
  });

  /// Rascunho tem de gritar, não sussurrar.
  ///
  /// O material fica cadastrado, a lista o mostra, e a IA não o usa em resposta
  /// nenhuma. A única pista disso era um selo cinza de 10px com a explicação
  /// escondida num tooltip — e o desfecho previsível foi perguntar ao
  /// assistente sobre o que se acabou de cadastrar e ouvir que ele não sabe.
  testWidgets('rascunho avisa, em texto, que a IA ainda não usa o material', (
    tester,
  ) async {
    respondeCom();
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Rascunho'), findsOneWidget);
    expect(
      find.textContaining('A IA ainda não usa este material'),
      findsOneWidget,
      reason: 'o aviso não pode viver só num tooltip',
    );
    // A ação que falta vem rotulada: um ícone de "revisar" não diz que sem
    // isso o material não vale nada.
    expect(find.text('Enviar para a IA'), findsOneWidget);
  });

  testWidgets('material já na IA não repete o aviso', (tester) async {
    respondeCom(finalizado: true, vetorizado: true);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('A IA ainda não usa'), findsNothing);
    expect(find.text('Enviar para a IA'), findsNothing);
  });

  testWidgets('sem material, convida a ensinar algo', (tester) async {
    when(
      () => client.listMyTreinamentos(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMyTreinamentosResponse()));
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('A IA ainda não foi treinada'), findsOneWidget);
  });

  testWidgets('erro do servidor aparece na tela', (tester) async {
    when(
      () => client.listMyTreinamentos(any()),
    ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')));
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível'), findsOneWidget);
  });

  testWidgets('o diálogo de criação valida antes de enviar', (tester) async {
    when(
      () => client.listMyTreinamentos(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMyTreinamentosResponse()));
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ensinar algo novo'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    // Dentro da janela: SnackBar renderiza atrás do barrier modal.
    expect(find.text('Informe o assunto e o grupo.'), findsOneWidget);
    verifyNever(() => client.createMyTreinamento(any()));
  });

  testWidgets('conteúdo vazio também é barrado', (tester) async {
    when(
      () => client.listMyTreinamentos(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMyTreinamentosResponse()));
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ensinar algo novo'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ex: horario-de-funcionamento'),
      'horario',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: atendimento'),
      'atendimento',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Escreva o que a IA precisa saber.'), findsOneWidget);
  });

  testWidgets('criar material fecha a janela e recarrega a lista', (
    tester,
  ) async {
    when(
      () => client.listMyTreinamentos(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMyTreinamentosResponse()));
    when(() => client.createMyTreinamento(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.MyTreinamentoResponse(
          treinamento: proto.MyTreinamento(id: 1, tag: 'horario'),
        ),
      ),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ensinar algo novo'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ex: horario-de-funcionamento'),
      'horario',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: atendimento'),
      'atendimento',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'O que a IA precisa saber'),
      'Abrimos de segunda a sexta.',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Ensinar algo novo'), findsOneWidget); // só o botão
    verify(() => client.createMyTreinamento(any())).called(1);
    // Recarrega para o material novo aparecer: uma na montagem, outra depois.
    verify(() => client.listMyTreinamentos(any())).called(2);
  });

  testWidgets('erro ao criar fica dentro da janela, que não fecha', (
    tester,
  ) async {
    when(
      () => client.listMyTreinamentos(any()),
    ).thenAnswer((_) => respostaGrpc(proto.ListMyTreinamentosResponse()));
    when(() => client.createMyTreinamento(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.invalidArgument('tag já existe')),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ensinar algo novo'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: horario-de-funcionamento'),
      'horario',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: atendimento'),
      'atendimento',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'O que a IA precisa saber'),
      'texto',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('tag já existe'), findsOneWidget);
  });

  testWidgets('revisar leva o texto EDITADO, não o original', (tester) async {
    // O ponto do passo de revisão: é o texto da tela que vira vetor. Enviar o
    // original faria a revisão não valer nada.
    respondeCom();
    when(
      () => client.finalizarMyTreinamento(any()),
    ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar para a IA'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Abrimos de segunda a sexta.'),
      'Abrimos de segunda a sábado.',
    );
    await tester.tap(find.text('Aceitar e treinar'));
    await tester.pumpAndSettle();

    final enviado =
        verify(
              () => client.finalizarMyTreinamento(captureAny()),
            ).captured.single
            as proto.FinalizarMyTreinamentoRequest;
    expect(enviado.conteudo, 'Abrimos de segunda a sábado.');
  });

  testWidgets('revisão com texto vazio é barrada', (tester) async {
    respondeCom();
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enviar para a IA'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Abrimos de segunda a sexta.'),
      '   ',
    );
    await tester.tap(find.text('Aceitar e treinar'));
    await tester.pumpAndSettle();

    expect(find.text('O conteúdo não pode ficar vazio.'), findsOneWidget);
    verifyNever(() => client.finalizarMyTreinamento(any()));
  });

  testWidgets('remover pede confirmação e avisa o efeito', (tester) async {
    respondeCom();
    when(
      () => client.removerMyTreinamento(any()),
    ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();

    expect(find.textContaining('deixa de usar'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    verify(() => client.removerMyTreinamento(any())).called(1);
    expect(find.text('Material removido.'), findsOneWidget);
  });

  testWidgets('cancelar a remoção não chama o servidor', (tester) async {
    respondeCom();
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => client.removerMyTreinamento(any()));
  });
}

/// A tela não sabia que o material tinha ficado pronto.
///
/// Quem vetoriza é o worker, minutos depois de aceitar. O cartão seguia
/// "Processando" em amarelo mesmo com o material já ativo no servidor, e a
/// única saída era recarregar no chute — foi exatamente o que aconteceu no
/// primeiro treinamento real.
void atualizaSozinhaEnquantoProcessa() {
  final getIt = GetIt.instance;
  late _MockAdminClient client;

  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  proto.MyTreinamento item({required bool vetorizado}) => proto.MyTreinamento(
    id: 1,
    tag: 'panfleto',
    grupo: 'produtos',
    conteudo: 'O panfleto tem 15x21 cm.',
    finalizado: true,
    vetorizado: vetorizado,
    criadoEm: Int64(DateTime(2026, 9, 12).millisecondsSinceEpoch),
    atualizadoEm: Int64(DateTime(2026, 9, 12).millisecondsSinceEpoch),
  );

  testWidgets('material que fica pronto aparece sem recarregar na mão', (
    tester,
  ) async {
    var chamadas = 0;
    when(() => client.listMyTreinamentos(any())).thenAnswer((_) {
      chamadas++;
      // Da segunda consulta em diante o worker já terminou.
      return respostaGrpc(
        proto.ListMyTreinamentosResponse(
          treinamentos: [item(vetorizado: chamadas > 1)],
        ),
      );
    });

    getIt.registerSingleton<TreinamentoController>(
      TreinamentoController(
        listar: ListarTreinamentosUsecase(
          repository: ListarTreinamentosRepository(
            datasource: ListarTreinamentosDatasource(client: client),
          ),
        ),
        criar: CriarTreinamentoUsecase(
          repository: CriarTreinamentoRepository(
            datasource: CriarTreinamentoDatasource(client: client),
          ),
        ),
        finalizar: FinalizarTreinamentoUsecase(
          repository: FinalizarTreinamentoRepository(
            datasource: FinalizarTreinamentoDatasource(client: client),
          ),
        ),
        remover: RemoverTreinamentoUsecase(
          repository: RemoverTreinamentoRepository(
            datasource: RemoverTreinamentoDatasource(client: client),
          ),
        ),
      ),
    );

    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const MaterialApp(home: TreinamentoPage()));
    await tester.pumpAndSettle();

    expect(find.text('Processando'), findsOneWidget);

    // Passa o intervalo do poll: a tela consulta de novo sozinha.
    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();

    expect(find.text('Ativo'), findsOneWidget);
    expect(find.text('Processando'), findsNothing);

    // E para de consultar: sem pendência, o timer é cancelado.
    final depois = chamadas;
    await tester.pump(const Duration(seconds: 40));
    await tester.pumpAndSettle();
    expect(
      chamadas,
      depois,
      reason: 'seguiu consultando sem nada em processamento',
    );
  });
}
