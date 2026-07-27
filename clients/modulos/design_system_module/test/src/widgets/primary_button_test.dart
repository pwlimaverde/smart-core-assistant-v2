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

    testWidgets('exibe spinner e desativa clique quando em loading', (
      tester,
    ) async {
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

    testWidgets('com ícone renderiza a variante FilledButton.icon', (
      tester,
    ) async {
      // O botão troca de construtor quando recebe ícone; sem este caso, a
      // variante usada nas ações principais do painel nunca é construída.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Salvar',
              icon: Icons.save,
              onPressed: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.text('Salvar'), findsOneWidget);
    });

    testWidgets('carregando ignora o ícone e mostra só o spinner', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PrimaryButton(
              label: 'Salvar',
              icon: Icons.save,
              isLoading: true,
              onPressed: null,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.save), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
