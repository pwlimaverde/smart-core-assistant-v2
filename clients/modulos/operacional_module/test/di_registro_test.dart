import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Todo usecase que o código pede ao `inject` precisa estar registrado.
///
/// Os testes de widget registram direto no GetIt o que usam, então uma tela
/// cujo usecase nunca foi registrado no módulo passa em todos eles e só quebra
/// no aplicativo. Foi exatamente assim que "Iniciar atendimento" chegou ao
/// teste de campo sem funcionar.
///
/// É uma leitura do código-fonte, e não uma montagem do módulo: montar exigiria
/// o transporte gRPC e o motor local inteiros, e o que se quer provar aqui é só
/// que o nome pedido tem um registro em algum lugar de `lib/`.
void main() {
  test('todo usecase injetado em lib/ tem registro em lib/', () {
    final fontes = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .toList();

    final pedido = RegExp(r'inject<(\w+Usecase)>\(\)');
    final registro = RegExp(
      r'(?:lazySingleton|singleton|factory)<(\w+Usecase)>\(',
    );

    final injetados = {
      for (final fonte in fontes)
        for (final m in pedido.allMatches(fonte)) m.group(1)!,
    };
    final registrados = {
      for (final fonte in fontes)
        for (final m in registro.allMatches(fonte)) m.group(1)!,
    };

    expect(injetados, isNotEmpty, reason: 'a leitura não achou nenhum inject');
    expect(
      injetados.difference(registrados).toList()..sort(),
      isEmpty,
      reason: 'usecases pedidos por inject<> sem registro no módulo',
    );
  });
}
