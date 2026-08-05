import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:treinamento_module/src/features/intents/data/datasources/intents_datasources.dart';
import 'package:treinamento_module/src/features/intents/data/repositories/intents_repositories.dart';
import 'package:treinamento_module/src/features/intents/domain/errors/intents_errors.dart';
import 'package:treinamento_module/src/features/intents/domain/parameters/intents_parameters.dart';
import 'package:treinamento_module/src/features/intents/domain/usecases/intents_usecases.dart';
import 'package:treinamento_module/src/features/intents/presentation/controllers/intents_controllers.dart';
import 'package:treinamento_module/src/features/intents/presentation/widgets/aba_intents.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(proto.ListMyIntentsRequest());
    registerFallbackValue(proto.MyIntentDados());
    registerFallbackValue(proto.UpdateMyIntentRequest());
    registerFallbackValue(proto.MyIntentIdRequest());
  });

  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  void registrar() {
    getIt.registerSingleton<IntentsController>(
      IntentsController(
        listar: ListarIntentsUsecase(
          repository: ListarIntentsRepository(
            datasource: ListarIntentsDatasource(client: client),
          ),
        ),
        criar: CriarIntentUsecase(
          repository: CriarIntentRepository(
            datasource: CriarIntentDatasource(client: client),
          ),
        ),
        atualizar: AtualizarIntentUsecase(
          repository: AtualizarIntentRepository(
            datasource: AtualizarIntentDatasource(client: client),
          ),
        ),
        remover: RemoverIntentUsecase(
          repository: RemoverIntentRepository(
            datasource: RemoverIntentDatasource(client: client),
          ),
        ),
      ),
    );
  }

  proto.MyIntent pb({
    int id = 1,
    String tag = 'falar-com-humano',
    String grupo = 'atendimento',
    bool vetorizada = true,
  }) =>
      proto.MyIntent(
        id: id,
        tag: tag,
        grupo: grupo,
        descricao: 'o cliente pede para falar com uma pessoa',
        exemplo: 'quero falar com um atendente',
        comportamento: 'transfira ao setor responsável',
        vetorizada: vetorizada,
      );

  void responde(List<proto.MyIntent> intents) {
    when(() => client.listMyIntents(any())).thenAnswer(
      (_) => respostaGrpc(proto.ListMyIntentsResponse(intents: intents)),
    );
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AbaIntents())),
    );
    await tester.pump();
  }

  testWidgets('lista as intenções com o que a IA passa a fazer', (
    tester,
  ) async {
    responde([pb()]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('falar-com-humano'), findsOneWidget);
    expect(
      find.text('o cliente pede para falar com uma pessoa'),
      findsOneWidget,
    );
    expect(find.textContaining('quero falar com um atendente'), findsOneWidget);
  });

  testWidgets('intenção sem vetor é marcada como em processamento', (
    tester,
  ) async {
    // Até o vetor existir, a intenção está no cadastro e não está na IA — sem
    // dizer isso, alguém cadastra, testa e conclui que o sistema não funciona.
    responde([pb(vetorizada: false)]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Processando'), findsOneWidget);
    expect(find.text('Ativa'), findsNothing);
  });

  testWidgets('intenção vetorizada aparece como ativa', (tester) async {
    responde([pb()]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Ativa'), findsOneWidget);
  });

  testWidgets('sem intenção nenhuma, explica quando usar uma', (tester) async {
    responde([]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.text('Nenhuma intenção cadastrada'), findsOneWidget);
    expect(find.textContaining('AGIR'), findsOneWidget);
  });

  testWidgets('erro do servidor vira tela de erro', (tester) async {
    when(() => client.listMyIntents(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.unavailable('fora do ar')),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('Não foi possível'), findsOneWidget);
  });

  testWidgets('criar sem comportamento é barrado dentro da janela', (
    tester,
  ) async {
    // Sem comportamento, casar a intenção não muda nada — seria cadastro sem
    // efeito nenhum.
    responde([]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nova intenção'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'ex: falar-com-humano'),
      'saudacao',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: o cliente pede para falar com uma pessoa'),
      'o cliente cumprimenta',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.text('Informe o que a IA deve fazer.'), findsOneWidget);
    verifyNever(() => client.createMyIntent(any()));
  });

  testWidgets('criar sem descrição é barrado', (tester) async {
    responde([]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nova intenção'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: falar-com-humano'),
      'saudacao',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Descreva quando'), findsOneWidget);
  });

  testWidgets('criar manda os cinco campos e recarrega', (tester) async {
    responde([]);
    when(() => client.createMyIntent(any())).thenAnswer(
      (_) => respostaGrpc(proto.MyIntentResponse(intent: pb())),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nova intenção'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: falar-com-humano'),
      'saudacao',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: atendimento'),
      'geral',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: o cliente pede para falar com uma pessoa'),
      'o cliente cumprimenta',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'ex: quero falar com um atendente'),
      'bom dia',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'O que a IA deve fazer'),
      'responda com a saudação da empresa',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final enviado = verify(() => client.createMyIntent(captureAny()))
        .captured
        .single as proto.MyIntentDados;
    expect(enviado.tag, 'saudacao');
    expect(enviado.grupo, 'geral');
    expect(enviado.descricao, 'o cliente cumprimenta');
    expect(enviado.exemplo, 'bom dia');
    expect(enviado.comportamento, 'responda com a saudação da empresa');
    // Uma na montagem, outra depois de criar.
    verify(() => client.listMyIntents(any())).called(2);
  });

  testWidgets('editar avisa que a intenção sai do ar até reprocessar', (
    tester,
  ) async {
    // Salvar zera o vetor no servidor: o texto mudou, e o vetor antigo faria a
    // busca casar pelo que a intenção era.
    responde([pb()]);
    when(() => client.updateMyIntent(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Editar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('volta para processamento'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'transfira ao setor responsável'),
      'transfira ao suporte',
    );
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    final enviado = verify(() => client.updateMyIntent(captureAny()))
        .captured
        .single as proto.UpdateMyIntentRequest;
    expect(enviado.id, 1);
    expect(enviado.dados.comportamento, 'transfira ao suporte');
  });

  testWidgets('remover confirma e diz que o material não é afetado', (
    tester,
  ) async {
    responde([pb()]);
    when(() => client.removeMyIntent(any())).thenAnswer(
      (_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)),
    );
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    expect(find.textContaining('material treinado não é afetado'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Remover'));
    await tester.pumpAndSettle();

    verify(() => client.removeMyIntent(any())).called(1);
    expect(find.text('Intenção removida.'), findsOneWidget);
  });

  testWidgets('cancelar a remoção não chama o servidor', (tester) async {
    responde([pb()]);
    registrar();

    await montar(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Remover'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    verifyNever(() => client.removeMyIntent(any()));
  });

  test('tag duplicada volta com a mensagem do servidor', () async {
    // A UNIQUE (tenant, tag, grupo) diz qual dupla colidiu; reescrever a
    // mensagem aqui perderia essa informação.
    when(() => client.createMyIntent(any())).thenAnswer(
      (_) => falhaGrpc(
        proto.GrpcError.alreadyExists('já existe uma intenção "saudacao"'),
      ),
    );

    final res = await CriarIntentUsecase(
      repository: CriarIntentRepository(
        datasource: CriarIntentDatasource(client: client),
      ),
    )(
      const CriarIntentParameters(
        dados: DadosIntent(
          tag: 'saudacao',
          grupo: '',
          descricao: 'x',
          exemplo: '',
          comportamento: 'y',
        ),
      ),
    );

    final erro = (res as Failure).error;
    expect(erro, isA<IntentsRecusado>());
    expect(erro.message, contains('saudacao'));
  });

  test('sessão expirada é distinguida de servidor fora do ar', () async {
    when(() => client.listMyIntents(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.unauthenticated('expirou')),
    );

    final res = await ListarIntentsUsecase(
      repository: ListarIntentsRepository(
        datasource: ListarIntentsDatasource(client: client),
      ),
    )(noParams);

    expect((res as Failure).error, isA<IntentsAcessoNegado>());
  });
}
