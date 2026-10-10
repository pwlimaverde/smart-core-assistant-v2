import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_core_tenant/platform/splash_atualizacao.dart';

void main() {
  testWidgets('mostra a splash até a verificação terminar e só então o app', (
    tester,
  ) async {
    final verificacao = Completer<void>();

    await tester.pumpWidget(
      SplashAtualizacao(
        verificacao: () => verificacao.future,
        depois: () async => const MaterialApp(home: Text('app pronto')),
      ),
    );

    expect(find.text('Verificando atualizações…'), findsOneWidget);
    expect(find.text('app pronto'), findsNothing);

    verificacao.complete();
    await tester.pumpAndSettle();

    expect(find.text('app pronto'), findsOneWidget);
    expect(find.text('Verificando atualizações…'), findsNothing);
  });
}
