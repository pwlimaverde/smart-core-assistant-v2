import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/streams/atendimento_evento_stream.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/colagem/leitor_de_imagem_colada.dart';
import 'package:operacional_module/src/features/atendimento/presentation/pages/chat_page.dart';

import '../../support/fake_gateway.dart';

/// PNG 1x1 de verdade: a prévia decodifica sem erro.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

/// A área de transferência sob controle do teste.
class _LeitorFalso implements LeitorDeImagemColada {
  bool texto = false;
  ImagemColada? imagem;
  int leituras = 0;

  @override
  Future<bool> temTexto() async => texto;

  @override
  Future<ImagemColada?> lerImagem() async {
    leituras++;
    return imagem;
  }
}

/// P3 — Ctrl+V de imagem no compositor da conversa.
void main() {
  final getIt = GetIt.instance;

  late FakeAtendimentoGateway gateway;
  late _LeitorFalso leitor;

  /// O texto que a colagem normal do campo encontra.
  String? textoNaArea;

  setUp(() {
    textoNaArea = null;
    gateway = FakeAtendimentoGateway(
      thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 8, 1))],
    );
    leitor = _LeitorFalso()
      ..imagem = ImagemColada(bytesPng: _png, formatoOriginal: 'bmp');
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
    // A colagem de texto do campo segue o caminho normal e lê o texto pelo
    // canal da plataforma; aqui ele responde com o que o teste definiu.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (chamada) async => switch (chamada.method) {
        'Clipboard.getData' =>
          textoNaArea == null ? null : <String, dynamic>{'text': textoNaArea},
        'Clipboard.hasStrings' => <String, dynamic>{
          'value': textoNaArea != null,
        },
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PainelDeConversa(atendimentoId: 7, leitorDeImagem: leitor),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> colarComCtrlV(WidgetTester tester) async {
    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> desmontar(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets('Ctrl+V com imagem abre a prévia e "Enviar" manda o PNG', (
    tester,
  ) async {
    await montar(tester);

    await colarComCtrlV(tester);

    expect(find.text('Enviar imagem?'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Enviar'));
    await tester.pumpAndSettle();

    expect(gateway.chamadasEnviarMidia, 1);
    expect(gateway.mimetypeEnviado, 'image/png');
    expect(gateway.nomeArquivoEnviado, matches(RegExp(r'^colado_\d+\.png$')));
    expect(gateway.legendaEnviada, isEmpty);
    expect(gateway.pttEnviado, isFalse);
    expect(gateway.bytesEnviados, _png.length);
    await desmontar(tester);
  });

  testWidgets('"Cancelar" na prévia não envia', (tester) async {
    await montar(tester);

    await colarComCtrlV(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(find.text('Enviar imagem?'), findsNothing);
    expect(gateway.chamadasEnviarMidia, 0);
    await desmontar(tester);
  });

  testWidgets('Ctrl+V com texto cola o texto e não abre a prévia', (
    tester,
  ) async {
    leitor.texto = true;
    textoNaArea = 'bom dia';
    await montar(tester);

    await colarComCtrlV(tester);

    // O atalho não foi consumido: o texto entrou no campo.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      'bom dia',
    );
    expect(find.text('Enviar imagem?'), findsNothing);
    expect(leitor.leituras, 0);
    expect(gateway.chamadasEnviarMidia, 0);
    await desmontar(tester);
  });

  testWidgets('Ctrl+V sem imagem não abre nada nem avisa', (tester) async {
    leitor.imagem = null;
    await montar(tester);

    await colarComCtrlV(tester);

    expect(leitor.leituras, 1);
    expect(find.text('Enviar imagem?'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    await desmontar(tester);
  });

  testWidgets('na aba "Nota interna" o Ctrl+V não oferece imagem', (
    tester,
  ) async {
    await montar(tester);
    await tester.tap(find.text('Nota interna'));
    await tester.pumpAndSettle();

    await colarComCtrlV(tester);

    expect(find.text('Enviar imagem?'), findsNothing);
    expect(leitor.leituras, 0);
    await desmontar(tester);
  });

  testWidgets('imagem acima de 5 MB é recusada com aviso, sem prévia', (
    tester,
  ) async {
    leitor.imagem = ImagemColada(
      bytesPng: Uint8List(tetoDeImagemEmBytes + 1),
      formatoOriginal: 'png',
    );
    await montar(tester);

    await colarComCtrlV(tester);

    expect(find.text('Enviar imagem?'), findsNothing);
    expect(find.textContaining('O limite é 5 MB'), findsOneWidget);
    expect(gateway.chamadasEnviarMidia, 0);
    await desmontar(tester);
  });

  testWidgets('V sem Ctrl não lê a área de transferência', (tester) async {
    await montar(tester);
    await tester.tap(find.byType(TextField));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pumpAndSettle();

    expect(leitor.leituras, 0);
    expect(find.text('Enviar imagem?'), findsNothing);
    await desmontar(tester);
  });
}
