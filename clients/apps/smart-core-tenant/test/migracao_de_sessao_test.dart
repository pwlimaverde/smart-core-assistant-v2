import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_core_tenant/platform/migracao_de_sessao_native.dart';

void main() {
  late Directory raiz;
  late Directory origem;
  late Directory destino;

  setUp(() async {
    raiz = await Directory.systemTemp.createTemp('migracao_sessao_');
    origem = Directory('${raiz.path}/antiga');
    destino = Directory('${raiz.path}/nova');
  });

  tearDown(() async {
    await raiz.delete(recursive: true);
  });

  test('copia os cofres que o destino não tem', () async {
    await origem.create();
    await File('${origem.path}/refresh_token.secure').writeAsString('antigo');
    await File('${origem.path}/outro.secure').writeAsString('x');

    await copiarCofres(origem: origem, destino: destino);

    expect(
      await File('${destino.path}/refresh_token.secure').readAsString(),
      'antigo',
    );
    expect(await File('${destino.path}/outro.secure').exists(), isTrue);
  });

  test('nunca sobrescreve um cofre que o destino já tem', () async {
    await origem.create();
    await File('${origem.path}/refresh_token.secure').writeAsString('antigo');
    await destino.create();
    await File('${destino.path}/refresh_token.secure').writeAsString('novo');

    await copiarCofres(origem: origem, destino: destino);

    expect(
      await File('${destino.path}/refresh_token.secure').readAsString(),
      'novo',
    );
  });

  test('ignora arquivos que não são cofres', () async {
    await origem.create();
    await File('${origem.path}/notas.txt').writeAsString('x');

    await copiarCofres(origem: origem, destino: destino);

    expect(await File('${destino.path}/notas.txt').exists(), isFalse);
  });

  test('sem pasta antiga, não cria nada e não lança', () async {
    await copiarCofres(origem: origem, destino: destino);

    expect(await destino.exists(), isFalse);
  });
}
