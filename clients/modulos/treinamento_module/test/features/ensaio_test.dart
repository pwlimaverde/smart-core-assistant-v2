import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:treinamento_module/src/features/ensaio/data/datasources/ensaio_datasources.dart';
import 'package:treinamento_module/src/features/ensaio/data/repositories/ensaio_repositories.dart';
import 'package:treinamento_module/src/features/ensaio/domain/errors/ensaio_errors.dart';
import 'package:treinamento_module/src/features/ensaio/domain/model/ensaio.dart';
import 'package:treinamento_module/src/features/ensaio/domain/parameters/ensaio_parameters.dart';
import 'package:treinamento_module/src/features/ensaio/domain/usecases/ensaio_usecases.dart';
import 'package:treinamento_module/src/features/ensaio/presentation/controllers/ensaio_controllers.dart';
import 'package:treinamento_module/src/features/ensaio/presentation/widgets/aba_ensaio.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

void main() {
  late _MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(() => registerFallbackValue(proto.TestarPerguntaRequest()));
  setUp(() => client = _MockAdminClient());
  tearDown(() => getIt.reset());

  TestarPerguntaUsecase usecase() => TestarPerguntaUsecase(
        repository: TestarPerguntaRepository(
          datasource: TestarPerguntaDatasource(client: client),
        ),
      );

  void registrar() {
    getIt.registerSingleton<EnsaioController>(
      EnsaioController(testar: usecase()),
    );
  }

  void responde({
    String resposta = 'Sim, entregamos aos sábados.',
    String comportamento = '',
    List<proto.TrechoUsado> trechos = const [],
    bool transferiria = false,
    String fluxo = '',
  }) {
    when(() => client.testarPergunta(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.TestarPerguntaResponse(
          resposta: resposta,
          comportamentoAplicado: comportamento,
          trechos: trechos,
          transferiria: transferiria,
          fluxoTransferencia: fluxo,
        ),
      ),
    );
  }

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AbaEnsaio())),
    );
    await tester.pump();
  }

  Future<void> perguntar(WidgetTester tester, String texto) async {
    await tester.enterText(find.byType(TextField), texto);
    await tester.tap(find.text('Testar'));
    await tester.pumpAndSettle();
  }

  group('semelhança', () {
    test('distância vira porcentagem para quem lê a tela', () {
      // Distância de cosseno é a linguagem do banco, não a de quem treina.
      expect(const TrechoUsado(conteudo: 'x', distancia: 0).semelhanca, 100);
      expect(const TrechoUsado(conteudo: 'x', distancia: 0.25).semelhanca, 75);
      expect(const TrechoUsado(conteudo: 'x', distancia: 1).semelhanca, 0);
    });

    test('distância fora da faixa não gera porcentagem absurda', () {
      // O pgvector pode devolver distância acima de 1 em espaços não
      // normalizados; -50% de semelhança não significaria nada na tela.
      expect(const TrechoUsado(conteudo: 'x', distancia: 1.8).semelhanca, 0);
    });
  });

  group('AbaEnsaio', () {
    testWidgets('antes do primeiro teste, convida a perguntar', (tester) async {
      registrar();

      await montar(tester);

      expect(find.text('Faça uma pergunta'), findsOneWidget);
    });

    testWidgets('pergunta vazia não chama o servidor', (tester) async {
      registrar();

      await montar(tester);
      await tester.tap(find.text('Testar'));
      await tester.pumpAndSettle();

      verifyNever(() => client.testarPergunta(any()));
    });

    testWidgets('mostra a resposta e a pergunta que a gerou', (tester) async {
      // Sem a pergunta ao lado, quem digitou um texto longo perde a referência.
      responde();
      registrar();

      await montar(tester);
      await perguntar(tester, 'vocês entregam no sábado?');

      expect(find.text('Sim, entregamos aos sábados.'), findsOneWidget);
      expect(find.text('"vocês entregam no sábado?"'), findsOneWidget);
    });

    testWidgets('mostra o material consultado com a semelhança', (
      tester,
    ) async {
      // É a semelhança que explica por que um trecho entrou e outro não.
      responde(
        trechos: [
          proto.TrechoUsado(
            conteudo: 'Entregamos de segunda a sábado.',
            distancia: 0.1,
          ),
        ],
      );
      registrar();

      await montar(tester);
      await perguntar(tester, 'entregam sábado?');

      expect(find.text('Entregamos de segunda a sábado.'), findsOneWidget);
      expect(find.text('90% de semelhança'), findsOneWidget);
    });

    testWidgets('resposta sem contexto nenhum é sinalizada', (tester) async {
      // A resposta pode parecer boa — o modelo inventa. É justamente aí que
      // quem treina precisa ser avisado.
      responde(resposta: 'Claro, entregamos!');
      registrar();

      await montar(tester);
      await perguntar(tester, 'entregam em marte?');

      expect(find.textContaining('não saiu do seu treinamento'), findsOneWidget);
    });

    testWidgets('com material casado, não acusa falta de contexto', (
      tester,
    ) async {
      responde(
        trechos: [
          proto.TrechoUsado(conteudo: 'Entregamos aos sábados.', distancia: 0.2),
        ],
      );
      registrar();

      await montar(tester);
      await perguntar(tester, 'entregam sábado?');

      expect(find.textContaining('não saiu do seu treinamento'), findsNothing);
    });

    testWidgets('intenção aplicada aparece separada do material', (
      tester,
    ) async {
      responde(comportamento: 'transfira ao setor de entregas');
      registrar();

      await montar(tester);
      await perguntar(tester, 'quero falar de entrega');

      expect(find.text('Intenção aplicada'), findsOneWidget);
      expect(find.text('transfira ao setor de entregas'), findsOneWidget);
    });

    testWidgets('transferência é avisada — é decisão diferente de responder', (
      tester,
    ) async {
      responde(transferiria: true, fluxo: 'Suporte · Padrão');
      registrar();

      await montar(tester);
      await perguntar(tester, 'meu pedido sumiu');

      expect(find.textContaining('Suporte · Padrão'), findsOneWidget);
    });

    testWidgets('IA fora do ar é distinguida de erro de treinamento', (
      tester,
    ) async {
      // A ação de quem lê é esperar, não mexer no material.
      when(() => client.testarPergunta(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.unavailable('a IA não respondeu')),
      );
      registrar();

      await montar(tester);
      await perguntar(tester, 'oi');

      expect(find.textContaining('A IA não respondeu agora'), findsOneWidget);
    });
  });

  test('os trechos chegam do mais parecido para o menos', () async {
    // A tela é lida de cima para baixo; a ordem é o que permite julgar o
    // resultado de relance.
    when(() => client.testarPergunta(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.TestarPerguntaResponse(
          resposta: 'ok',
          trechos: [
            proto.TrechoUsado(conteudo: 'longe', distancia: 0.9),
            proto.TrechoUsado(conteudo: 'perto', distancia: 0.1),
            proto.TrechoUsado(conteudo: 'meio', distancia: 0.5),
          ],
        ),
      ),
    );

    final res = await usecase()(
      const TestarPerguntaParameters(pergunta: 'x'),
    );

    final ensaio = (res as Success<Ensaio, EnsaioError>).value;
    expect(
      ensaio.trechos.map((t) => t.conteudo),
      ['perto', 'meio', 'longe'],
    );
  });

  test('sessão expirada é distinguida da IA fora do ar', () async {
    when(() => client.testarPergunta(any())).thenAnswer(
      (_) => falhaGrpc(proto.GrpcError.unauthenticated('expirou')),
    );

    final res = await usecase()(const TestarPerguntaParameters(pergunta: 'x'));

    expect((res as Failure).error, isA<EnsaioAcessoNegado>());
  });

  test('pergunta recusada pelo servidor volta com a mensagem dele', () async {
    when(() => client.testarPergunta(any())).thenAnswer(
      (_) =>
          falhaGrpc(proto.GrpcError.invalidArgument('escreva a pergunta a testar')),
    );

    final res = await usecase()(const TestarPerguntaParameters(pergunta: ' '));

    final erro = (res as Failure).error;
    expect(erro, isA<EnsaioPerguntaInvalida>());
    expect(erro.message, 'escreva a pergunta a testar');
  });
}
