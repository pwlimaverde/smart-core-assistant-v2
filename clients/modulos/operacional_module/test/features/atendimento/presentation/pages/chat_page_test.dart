import 'package:api_client/api_client.dart' show GrpcError;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ficha.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/chat_page.dart';
import 'package:operacional_module/src/features/atendimento/presentation/widgets/painel_ficha.dart';

import '../../support/fake_gateway.dart';

/// A conversa e a ficha são duas coisas independentes na mesma tela: uma pode
/// falhar sem levar a outra, e em janela estreita a ficha cede o espaço.
void main() {
  final getIt = GetIt.instance;

  tearDown(() => getIt.reset());

  void registrar(FakeAtendimentoGateway gateway) {
    final u = usecasesSobre(gateway);
    getIt
      ..registerSingleton<GetThreadUsecase>(u.thread)
      ..registerSingleton<SendOutboundMessageUsecase>(u.send)
      ..registerSingleton<AtendimentoEventoStream>(u.eventos)
      ..registerSingleton<GetFichaUsecase>(u.ficha)
      ..registerSingleton<CriarEtiquetaUsecase>(u.criarEtiqueta)
      ..registerSingleton<AlternarEtiquetaUsecase>(u.alternarEtiqueta)
      ..registerSingleton<CriarNotaUsecase>(u.criarNota);
  }

  Future<void> montar(
    WidgetTester tester,
    FakeAtendimentoGateway gateway, {
    double largura = 1400,
  }) async {
    tester.view.physicalSize = Size(largura, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    registrar(gateway);
    await tester.pumpWidget(
      const MaterialApp(home: ChatPage(atendimentoId: 7)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('mostra a conversa e a ficha lado a lado', (tester) async {
    final gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    )..ficha = const FichaAtendimento(
        catalogo: [],
        aplicadas: [
          Etiqueta(
            id: 1,
            nome: 'urgente',
            cor: '#ef4444',
            descricao: '',
            ativo: true,
          ),
        ],
        notas: [],
      );

    await montar(tester, gateway);

    expect(find.text('oi'), findsOneWidget);
    expect(find.byType(PainelFicha), findsOneWidget);
    expect(find.text('urgente'), findsOneWidget);
  });

  testWidgets('em janela estreita a ficha cede o espaço à conversa', (
    tester,
  ) async {
    // Ler e responder é o que não pode ficar sem espaço; as etiquetas
    // continuam visíveis no cartão do quadro.
    final gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    );

    await montar(tester, gateway, largura: 700);

    expect(find.text('oi'), findsOneWidget);
    expect(find.byType(PainelFicha), findsNothing);
  });

  testWidgets('a ficha falha sem derrubar a conversa', (tester) async {
    final gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    )..erroFicha = GrpcError.unavailable('fora do ar');

    await montar(tester, gateway);

    // A mensagem continua lá; só o painel mostra erro.
    expect(find.text('oi'), findsOneWidget);
    expect(find.textContaining('Não foi possível'), findsOneWidget);
  });

  testWidgets('conversa vazia convida a começar', (tester) async {
    final gateway = FakeAtendimentoGateway();

    await montar(tester, gateway);

    expect(find.text('Nenhuma mensagem ainda'), findsOneWidget);
  });

  testWidgets('erro do histórico vira tela de erro com retentar', (
    tester,
  ) async {
    final gateway = FakeAtendimentoGateway()
      ..erroThread = GrpcError.unavailable('fora do ar');

    await montar(tester, gateway);

    expect(find.textContaining('Não foi possível'), findsWidgets);
  });

  testWidgets('mensagem vazia não é enviada', (tester) async {
    final gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    );

    await montar(tester, gateway);
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(gateway.chamadasSend, 0);
  });

  testWidgets('enviar limpa o campo e chama o servidor', (tester) async {
    final gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    );

    await montar(tester, gateway);
    await tester.enterText(
      find.widgetWithText(TextField, 'Digite uma mensagem…'),
      'bom dia',
    );
    await tester.tap(find.byIcon(Icons.send));
    await tester.pumpAndSettle();

    expect(gateway.chamadasSend, 1);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller?.text,
      isEmpty,
    );
  });
}
