import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/presentation/gravacao/apagar_arquivo.dart';

/// P2b — no desktop (VM) o import condicional cai na versão com `dart:io`.
void main() {
  late Directory pasta;

  setUp(() => pasta = Directory.systemTemp.createTempSync('p2b_audio_'));
  tearDown(() {
    if (pasta.existsSync()) pasta.deleteSync(recursive: true);
  });

  test('apaga o áudio temporário', () async {
    final arquivo = File('${pasta.path}/ptt.m4a')..writeAsBytesSync([1, 2]);

    await apagarArquivoTemporario(arquivo.path);

    expect(arquivo.existsSync(), isFalse);
  });

  test('arquivo que já sumiu não é erro', () async {
    await expectLater(
      apagarArquivoTemporario('${pasta.path}/nao_existe.m4a'),
      completes,
    );
  });

  test('caminho vazio (web) não faz nada', () async {
    await expectLater(apagarArquivoTemporario(''), completes);
  });
}
