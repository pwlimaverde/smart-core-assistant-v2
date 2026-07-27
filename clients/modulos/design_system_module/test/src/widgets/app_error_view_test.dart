import 'package:design_system_module/src/widgets/app_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppErrorView', () {
    testWidgets('exibe mensagem e botão de retry condicionalmente', (
      tester,
    ) async {
      var retried = false;

      // Sem retry
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppErrorView(message: 'Erro desconhecido')),
        ),
      );

      expect(find.text('Erro desconhecido'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsNothing);

      // Com retry
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppErrorView(
              message: 'Erro com retry',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Tentar novamente'), findsOneWidget);
      await tester.tap(find.text('Tentar novamente'));
      expect(retried, isTrue);
    });
  });
}
