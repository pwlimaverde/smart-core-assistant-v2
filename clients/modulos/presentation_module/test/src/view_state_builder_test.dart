import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

class MockTestController extends MockCubit<ViewState<String>>
    implements BaseController<String> {}

void main() {
  group('ViewStateBuilder', () {
    late MockTestController mockController;

    setUp(() {
      mockController = MockTestController();
    });

    testWidgets('renderiza onInitial', (tester) async {
      when(() => mockController.state).thenReturn(InitialState<String>());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewStateBuilder<MockTestController, String>(
              controller: mockController,
              onSuccess: (context, data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renderiza onLoading', (tester) async {
      when(() => mockController.state).thenReturn(LoadingState<String>());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewStateBuilder<MockTestController, String>(
              controller: mockController,
              onSuccess: (context, data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renderiza onError', (tester) async {
      when(() => mockController.state).thenReturn(
        const ErrorState<String>(ErrorGeneric(message: 'Erro inesperado')),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewStateBuilder<MockTestController, String>(
              controller: mockController,
              onSuccess: (context, data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('Erro inesperado'), findsOneWidget);
    });

    testWidgets('renderiza onSuccess', (tester) async {
      when(() => mockController.state).thenReturn(const SuccessState<String>('carregou'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewStateBuilder<MockTestController, String>(
              controller: mockController,
              onSuccess: (context, data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('carregou'), findsOneWidget);
    });
  });
}
