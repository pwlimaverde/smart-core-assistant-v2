import 'package:design_system_module/src/widgets/app_empty_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppEmptyView', () {
    testWidgets(
      'renderiza título, ícone padrão e sem subtítulo quando omitido',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: AppEmptyView(title: 'Nada por aqui')),
          ),
        );

        expect(find.text('Nada por aqui'), findsOneWidget);
        expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
      },
    );

    testWidgets('renderiza subtítulo e ícone customizado quando informados', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AppEmptyView(
              title: 'Fila vazia',
              subtitle: 'Nenhum atendimento nesta etapa',
              icon: Icons.inbox,
            ),
          ),
        ),
      );

      expect(find.text('Fila vazia'), findsOneWidget);
      expect(find.text('Nenhum atendimento nesta etapa'), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsOneWidget);
      expect(find.byIcon(Icons.inbox_outlined), findsNothing);
    });
  });
}
