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

  testWidgets('rascunho oferece revisão', (tester) async {
    respondeCom();
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Rascunho'), findsOneWidget);
    expect(find.byTooltip('Revisar e enviar para a IA'), findsOneWidget);
  });

  testWidgets('sem material, convida a ensinar algo', (tester) async {
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyTreinamentosResponse()),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('A IA ainda não foi treinada'), findsOneWidget);
  });

  testWidgets('erro do servidor aparece na tela', (tester) async {
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível'), findsOneWidget);
  });

  testWidgets('o diálogo de criação valida antes de enviar', (tester) async {
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyTreinamentosResponse()),
    );
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
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyTreinamentosResponse()),
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
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Escreva o que a IA precisa saber.'), findsOneWidget);
  });

  testWidgets('criar material fecha a janela e recarrega a lista', (
    tester,
  ) async {
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyTreinamentosResponse()),
    );
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
    when(() => client.listMyTreinamentos(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyTreinamentosResponse()),
    );
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
    when(() => client.finalizarMyTreinamento(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Revisar e enviar para a IA'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Abrimos de segunda a sexta.'),
      'Abrimos de segunda a sábado.',
    );
    await tester.tap(find.text('Aceitar e treinar'));
    await tester.pumpAndSettle();

    final enviado = verify(() => client.finalizarMyTreinamento(captureAny()))
        .captured
        .single as proto.FinalizarMyTreinamentoRequest;
    expect(enviado.conteudo, 'Abrimos de segunda a sábado.');
  });

  testWidgets('revisão com texto vazio é barrada', (tester) async {
    respondeCom();
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Revisar e enviar para a IA'));
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
    when(() => client.removerMyTreinamento(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
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
