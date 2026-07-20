import 'package:design_system_module/src/widgets/kanban/kanban_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KanbanCard', () {
    testWidgets('renderiza o child e usa opacidade cheia quando não está arrastando', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanCard<String>(data: 'card-1', child: const Text('Card 1')),
          ),
        ),
      );

      expect(find.text('Card 1'), findsOneWidget);
      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, 1);
    });

    testWidgets('isDragging=true reduz a opacidade do card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KanbanCard<String>(
              data: 'card-1',
              isDragging: true,
              child: const Text('Card 1'),
            ),
          ),
        ),
      );

      final opacity = tester.widget<Opacity>(find.byType(Opacity).first);
      expect(opacity.opacity, 0.5);
    });

    testWidgets('carrega o data correto no Draggable e aceita drop num DragTarget', (
      tester,
    ) async {
      String? accepted;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                KanbanCard<String>(data: 'card-1', child: const Text('Card 1')),
                Expanded(
                  child: DragTarget<String>(
                    onAcceptWithDetails: (details) => accepted = details.data,
                    builder: (context, candidate, rejected) =>
                        Container(key: const Key('drop-area')),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final draggable = tester.widget<Draggable<String>>(find.byType(Draggable<String>));
      expect(draggable.data, 'card-1');

      final cardCenter = tester.getCenter(find.text('Card 1'));
      final dropCenter = tester.getCenter(find.byKey(const Key('drop-area')));

      final gesture = await tester.startGesture(cardCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.moveTo(dropCenter);
      await tester.pump(const Duration(milliseconds: 50));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(accepted, 'card-1');
    });
  });
}
