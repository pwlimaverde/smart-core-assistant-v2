import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/gravacao/gravador_de_audio.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/chat_page.dart';
import 'package:record/record.dart';

import '../../support/fake_gateway.dart';

class _MockGravador extends Mock implements AudioRecorder {}

/// P2b — o botão do microfone na conversa, sem microfone de verdade.
void main() {
  final getIt = GetIt.instance;

  setUpAll(() {
    registerFallbackValue(const RecordConfig());
    registerFallbackValue(AudioEncoder.aacLc);
  });

  late _MockGravador recorder;
  late DateTime agora;
  late List<String> apagados;
  late FakeAtendimentoGateway gateway;

  setUp(() {
    recorder = _MockGravador();
    agora = DateTime(2026, 10, 2, 10);
    apagados = [];
    gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    );
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(
      () => recorder.isEncoderSupported(any()),
    ).thenAnswer((_) async => true);
    when(
      () => recorder.start(any(), path: any(named: 'path')),
    ).thenAnswer((_) async {});
    when(() => recorder.stop()).thenAnswer((_) async => 'tmp/ptt.m4a');
    when(() => recorder.cancel()).thenAnswer((_) async {});
    when(() => recorder.dispose()).thenAnswer((_) async {});
  });

  tearDown(() => getIt.reset());

  Future<void> montar(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final u = usecasesSobre(gateway);
    getIt
      ..registerSingleton<GetThreadUsecase>(u.thread)
      ..registerSingleton<SendOutboundMessageUsecase>(u.send)
      ..registerSingleton<AtendimentoEventoStream>(u.eventos)
      ..registerSingleton<GetFichaUsecase>(u.ficha)
      ..registerSingleton<CriarEtiquetaUsecase>(u.criarEtiqueta)
      ..registerSingleton<AlternarEtiquetaUsecase>(u.alternarEtiqueta)
      ..registerSingleton<CriarNotaUsecase>(u.criarNota)
      ..registerSingleton<DefinirBotDaConversaUsecase>(u.definirBot)
      ..registerSingleton<DefinirValorCampoUsecase>(u.definirValorCampo)
      ..registerSingleton<EnviarMidiaUsecase>(
        EnviarMidiaUsecase(
          repository: EnviarMidiaRepository(
            datasource: EnviarMidiaDatasource(gateway: gateway),
          ),
        ),
      );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PainelDeConversa(
            atendimentoId: 7,
            criarGravador: () => GravadorDeAudio(
              criarGravador: () => recorder,
              caminhoDoAudio: () async => 'tmp/ptt.m4a',
              lerArquivo: (_) async => List<int>.filled(2048, 7),
              apagarArquivo: (caminho) async => apagados.add(caminho),
              agora: () => agora,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tocarNoMicrofone(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Gravar áudio'));
    await tester.pumpAndSettle();
  }

  Future<void> pararEEnviar(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Parar e enviar'));
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('start que falha avisa e o botão não trava', (tester) async {
    when(
      () => recorder.start(any(), path: any(named: 'path')),
    ).thenThrow(Exception('microfone ocupado'));
    await montar(tester);

    await tocarNoMicrofone(tester);

    expect(find.text('Não deu para usar o microfone.'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle), findsNothing);

    // Segunda tentativa chega ao gravador: nada ficou preso. O aviso sai da
    // frente antes, para o toque não cair nele.
    tester
        .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
        .removeCurrentSnackBar();
    await tester.pumpAndSettle();
    await tocarNoMicrofone(tester);
    verify(() => recorder.start(any(), path: any(named: 'path'))).called(2);
    expect(gateway.chamadasEnviarMidia, 0);
    await desmontar(tester);
  });

  testWidgets('encoder não suportado avisa sem gravar', (tester) async {
    when(
      () => recorder.isEncoderSupported(any()),
    ).thenAnswer((_) async => false);
    await montar(tester);

    await tocarNoMicrofone(tester);

    expect(find.text('Não deu para usar o microfone.'), findsOneWidget);
    verifyNever(() => recorder.start(any(), path: any(named: 'path')));
    await desmontar(tester);
  });

  testWidgets('sem permissão avisa sem gravar', (tester) async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => false);
    await montar(tester);

    await tocarNoMicrofone(tester);

    expect(find.text('Sem permissão para usar o microfone.'), findsOneWidget);
    verifyNever(() => recorder.start(any(), path: any(named: 'path')));
    await desmontar(tester);
  });

  testWidgets('áudio gravado sobe como m4a, sem legenda, e o temporário some', (
    tester,
  ) async {
    await montar(tester);

    await tocarNoMicrofone(tester);
    expect(find.byIcon(Icons.stop_circle), findsOneWidget);

    agora = agora.add(const Duration(seconds: 4));
    await pararEEnviar(tester);

    expect(gateway.chamadasEnviarMidia, 1);
    expect(gateway.mimetypeEnviado, 'audio/mp4');
    expect(gateway.nomeArquivoEnviado, 'audio.m4a');
    expect(gateway.legendaEnviada, isEmpty);
    expect(gateway.bytesEnviados, 2048);
    expect(apagados, ['tmp/ptt.m4a']);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    await desmontar(tester);
  });

  testWidgets('gravação de menos de 1 s não é enviada', (tester) async {
    await montar(tester);

    await tocarNoMicrofone(tester);
    agora = agora.add(const Duration(milliseconds: 400));
    await pararEEnviar(tester);

    expect(gateway.chamadasEnviarMidia, 0);
    expect(
      find.text('Áudio curto demais: grave por pelo menos 1 segundo.'),
      findsOneWidget,
    );
    verify(() => recorder.cancel()).called(1);
    expect(apagados, ['tmp/ptt.m4a']);
    await desmontar(tester);
  });

  testWidgets('stop que falha avisa e libera o botão', (tester) async {
    when(() => recorder.stop()).thenThrow(Exception('nativo'));
    await montar(tester);

    await tocarNoMicrofone(tester);
    agora = agora.add(const Duration(seconds: 2));
    await pararEEnviar(tester);

    expect(find.text('Não deu para concluir a gravação.'), findsOneWidget);
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
    expect(gateway.chamadasEnviarMidia, 0);
    await desmontar(tester);
  });

  testWidgets('fechar a conversa gravando solta o microfone', (tester) async {
    await montar(tester);
    await tocarNoMicrofone(tester);

    await desmontar(tester);

    verify(() => recorder.cancel()).called(1);
    verify(() => recorder.dispose()).called(1);
    expect(apagados, ['tmp/ptt.m4a']);
  });

  testWidgets('abrir e fechar a conversa não acorda o microfone', (
    tester,
  ) async {
    await montar(tester);
    await desmontar(tester);

    verifyNever(() => recorder.hasPermission());
    verifyNever(() => recorder.dispose());
  });
}
