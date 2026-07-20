import 'package:design_system_module/src/widgets/kanban/kanban_card.dart';
import 'package:design_system_module/src/widgets/kanban/kanban_drop_column.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KanbanDropColumn', () {
    testWidgets('renderiza título, contador e os children', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanDropColumn<String>(
              title: 'Em atendimento',
              itemCount: 2,
              onAccept: (_) {},
              children: const [Text('Item A'), Text('Item B')],
            ),
          ),
        ),
      );

      expect(find.text('Em atendimento'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Item A'), findsOneWidget);
      expect(find.text('Item B'), findsOneWidget);
    });

    testWidgets(
      'aceita o drop de um KanbanCard e chama onAccept com o data carregado',
      (tester) async {
        String? accepted;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  KanbanCard<String>(data: 'atendimento-1', child: const Text('Card')),
                  Expanded(
                    child: KanbanDropColumn<String>(
                      title: 'Fila',
                      itemCount: 0,
                      onAccept: (data) => accepted = data,
                      children: const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final cardCenter = tester.getCenter(find.text('Card'));
        final columnCenter = tester.getCenter(find.byType(KanbanDropColumn<String>));

        final gesture = await tester.startGesture(cardCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(columnCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(accepted, 'atendimento-1');
      },
    );

    testWidgets(
      'onWillAccept=false rejeita o drop: onAccept não é chamado',
      (tester) async {
        var acceptChamado = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  KanbanCard<String>(data: 'atendimento-1', child: const Text('Card')),
                  Expanded(
                    child: KanbanDropColumn<String>(
                      title: 'Fila',
                      itemCount: 0,
                      onWillAccept: (_) => false,
                      onAccept: (_) => acceptChamado = true,
                      children: const [],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        final cardCenter = tester.getCenter(find.text('Card'));
        final columnCenter = tester.getCenter(find.byType(KanbanDropColumn<String>));

        final gesture = await tester.startGesture(cardCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.moveTo(columnCenter);
        await tester.pump(const Duration(milliseconds: 50));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(acceptChamado, isFalse);
      },
    );
  });
}
