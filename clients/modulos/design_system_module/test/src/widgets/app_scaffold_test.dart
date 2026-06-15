import 'package:design_system_module/src/widgets/app_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppScaffold', () {
    testWidgets('exibe AppBar apenas se título for fornecido', (tester) async {
      // Sem título
      await tester.pumpWidget(
        const MaterialApp(
          home: AppScaffold(
            body: Text('Corpo'),
          ),
        ),
      );

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('Corpo'), findsOneWidget);

      // Com título
      await tester.pumpWidget(
        const MaterialApp(
          home: AppScaffold(
            title: 'Minha Tela',
            body: Text('Corpo'),
          ),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Minha Tela'), findsOneWidget);
    });
  });
}
