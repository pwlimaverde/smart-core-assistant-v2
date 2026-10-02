import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operacional_module/src/features/atendimento/presentation/gravacao/gravador_de_audio.dart';
import 'package:record/record.dart';

class _MockGravador extends Mock implements AudioRecorder {}

/// P2b — o gravador sem microfone: o `AudioRecorder` é falso, o relógio é
/// manual e ler/apagar arquivo são anotados em vez de tocar o disco.
void main() {
  setUpAll(() {
    registerFallbackValue(const RecordConfig());
    registerFallbackValue(AudioEncoder.aacLc);
  });

  late _MockGravador recorder;
  late DateTime agora;
  late int criados;
  late List<String> apagados;
  late List<int> bytesNoDisco;
  Object? erroAoLer;
  Object? erroAoApagar;

  GravadorDeAudio novo() => GravadorDeAudio(
    criarGravador: () {
      criados++;
      return recorder;
    },
    caminhoDoAudio: () async => 'tmp/ptt.m4a',
    lerArquivo: (caminho) async {
      if (erroAoLer != null) throw erroAoLer!;
      return bytesNoDisco;
    },
    apagarArquivo: (caminho) async {
      if (erroAoApagar != null) throw erroAoApagar!;
      apagados.add(caminho);
    },
    agora: () => agora,
  );

  setUp(() {
    recorder = _MockGravador();
    agora = DateTime(2026, 10, 2, 10);
    criados = 0;
    apagados = [];
    bytesNoDisco = [1, 2, 3, 4];
    erroAoLer = null;
    erroAoApagar = null;
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

  test('o áudio gravado sobe como m4a/audio/mp4', () {
    expect(nomeDoAudioGravado, endsWith('.m4a'));
    expect(mimetypeDoAudioGravado, 'audio/mp4');
    expect(GravadorDeAudio.config.encoder, AudioEncoder.aacLc);
  });

  test('o AudioRecorder só nasce no primeiro uso', () async {
    final g = novo();
    expect(criados, 0);
    await g.dispose();
    expect(criados, 0);
    verifyNever(() => recorder.dispose());
  });

  test('temPermissao pergunta ao gravador', () async {
    when(() => recorder.hasPermission()).thenAnswer((_) async => false);
    expect(await novo().temPermissao(), isFalse);
  });

  test('iniciar confere o encoder e grava em aacLc', () async {
    final g = novo();
    await g.iniciar();

    expect(g.gravando, isTrue);
    verify(() => recorder.isEncoderSupported(AudioEncoder.aacLc)).called(1);
    final config =
        verify(
              () => recorder.start(captureAny(), path: 'tmp/ptt.m4a'),
            ).captured.single
            as RecordConfig;
    expect(config.encoder, AudioEncoder.aacLc);
  });

  test('iniciar duas vezes não reinicia a gravação', () async {
    final g = novo();
    await g.iniciar();
    await g.iniciar();
    verify(() => recorder.start(any(), path: any(named: 'path'))).called(1);
  });

  test('encoder ausente lança e nem tenta gravar', () async {
    when(
      () => recorder.isEncoderSupported(any()),
    ).thenAnswer((_) async => false);
    final g = novo();

    await expectLater(g.iniciar(), throwsStateError);
    expect(g.gravando, isFalse);
    verifyNever(() => recorder.start(any(), path: any(named: 'path')));
  });

  test('start que falha deixa o gravador pronto para tentar de novo', () async {
    var tentativas = 0;
    when(() => recorder.start(any(), path: any(named: 'path'))).thenAnswer((
      _,
    ) async {
      if (tentativas++ == 0) throw Exception('microfone ocupado');
    });
    final g = novo();

    await expectLater(g.iniciar(), throwsException);
    expect(g.gravando, isFalse);

    await g.iniciar();
    expect(g.gravando, isTrue);
  });

  test('menos de 1 s é descartado e o arquivo apagado', () async {
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(milliseconds: 600));

    final fim = await g.parar();

    expect(fim, isA<GravacaoCurta>());
    expect(g.gravando, isFalse);
    verify(() => recorder.cancel()).called(1);
    verifyNever(() => recorder.stop());
    expect(apagados, ['tmp/ptt.m4a']);
  });

  test('gravação válida devolve os bytes e apaga o temporário', () async {
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(seconds: 3));

    final fim = await g.parar();

    expect(fim, isA<AudioGravado>());
    final audio = fim as AudioGravado;
    expect(audio.bytes, [1, 2, 3, 4]);
    expect(audio.duracao, const Duration(seconds: 3));
    expect(apagados, ['tmp/ptt.m4a']);
    expect(g.gravando, isFalse);
  });

  test('exatamente 1 s já vale', () async {
    final g = novo();
    await g.iniciar();
    agora = agora.add(duracaoMinimaDoAudio);

    expect(await g.parar(), isA<AudioGravado>());
  });

  test('stop sem caminho é gravação vazia', () async {
    when(() => recorder.stop()).thenAnswer((_) async => null);
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(seconds: 2));

    expect(await g.parar(), isA<GravacaoVazia>());
    expect(apagados, ['tmp/ptt.m4a']);
  });

  test('arquivo vazio é gravação vazia', () async {
    bytesNoDisco = [];
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(seconds: 2));

    expect(await g.parar(), isA<GravacaoVazia>());
  });

  test('parar sem ter gravado não faz nada', () async {
    final g = novo();
    expect(await g.parar(), isA<GravacaoVazia>());
    expect(criados, 0);
  });

  test('falha ao ler ainda apaga o temporário', () async {
    erroAoLer = Exception('disco');
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(seconds: 2));

    await expectLater(g.parar(), throwsException);
    expect(apagados, ['tmp/ptt.m4a']);
    expect(g.gravando, isFalse);
  });

  test('não conseguir apagar não impede o envio', () async {
    erroAoApagar = Exception('em uso');
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(seconds: 2));

    expect(await g.parar(), isA<AudioGravado>());
  });

  test('dispose no meio da gravação descarta e libera', () async {
    final g = novo();
    await g.iniciar();

    await g.dispose();

    verify(() => recorder.cancel()).called(1);
    verify(() => recorder.dispose()).called(1);
    expect(apagados, ['tmp/ptt.m4a']);
    expect(g.gravando, isFalse);
  });

  test('dispose depois de gravar só libera', () async {
    final g = novo();
    await g.iniciar();
    agora = agora.add(const Duration(seconds: 2));
    await g.parar();

    await g.dispose();

    verifyNever(() => recorder.cancel());
    verify(() => recorder.dispose()).called(1);
  });

  test('falha ao liberar não escapa', () async {
    when(() => recorder.dispose()).thenThrow(Exception('nativo'));
    final g = novo();
    await g.temPermissao();

    await expectLater(g.dispose(), completes);
  });
}
