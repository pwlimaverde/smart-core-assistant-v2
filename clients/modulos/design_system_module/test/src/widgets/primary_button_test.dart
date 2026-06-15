import 'package:design_system_module/src/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PrimaryButton', () {
    testWidgets('exibe label e executa callback ao clicar', (tester) async {
      var clicou = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Clique-me',
              onPressed: () => clicou = true,
            ),
          ),
        ),
      );

      expect(find.text('Clique-me'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(PrimaryButton));
      expect(clicou, isTrue);
    });

    testWidgets('exibe spinner e desativa clique quando em loading', (tester) async {
      var clicou = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Carregando...',
              isLoading: true,
              onPressed: () => clicou = true,
            ),
          ),
        ),
      );

      expect(find.text('Carregando...'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byType(PrimaryButton));
      expect(clicou, isFalse);
    });
  });
}
