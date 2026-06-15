import 'package:design_system_module/src/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppCard', () {
    testWidgets('renderiza widget filho e responde ao clique', (tester) async {
      var clicou = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppCard(
              onTap: () => clicou = true,
              child: const Text('Conteúdo do Card'),
            ),
          ),
        ),
      );

      expect(find.text('Conteúdo do Card'), findsOneWidget);
      await tester.tap(find.text('Conteúdo do Card'));
      expect(clicou, isTrue);
    });
  });
}
