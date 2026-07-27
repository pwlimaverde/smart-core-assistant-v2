import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

class MockTestController extends MockCubit<ViewState<String>>
    implements BaseController<String> {}

class TestModulePage extends ModulePage<MockTestController, String> {
  final VoidCallback? onInitCallback;
  const TestModulePage({super.key, this.onInitCallback});

  @override
  void onInit(BuildContext context) {
    super.onInit(context);
    onInitCallback?.call();
  }

  @override
  Widget onSuccess(BuildContext context, String data) => Text('Sucesso: $data');
}

void main() {
  group('ModulePage', () {
    late MockTestController mockController;
    final getIt = GetIt.instance;

    setUp(() {
      mockController = MockTestController();
      getIt.registerSingleton<MockTestController>(mockController);
    });

    tearDown(() {
      getIt.reset();
    });

    testWidgets('chama onInit na montagem e renderiza estado de sucesso', (tester) async {
      var onInitChamado = false;
      when(() => mockController.state).thenReturn(const SuccessState<String>('ok'));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TestModulePage(
              onInitCallback: () => onInitChamado = true,
            ),
          ),
        ),
      );

      await tester.pump();

      expect(onInitChamado, isTrue);
      expect(find.text('Sucesso: ok'), findsOneWidget);
    });

    testWidgets('estado inicial renderiza vazio por padrão', (tester) async {
      when(
        () => mockController.state,
      ).thenReturn(const InitialState<String>());

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TestModulePage())),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('estado de carregamento renderiza spinner por padrão', (
      tester,
    ) async {
      when(
        () => mockController.state,
      ).thenReturn(const LoadingState<String>());

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TestModulePage())),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('estado de erro renderiza a mensagem do AppError por padrão', (
      tester,
    ) async {
      when(() => mockController.state).thenReturn(
        const ErrorState<String>(ErrorGeneric('falhou de verdade')),
      );

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TestModulePage())),
      );

      expect(find.text('falhou de verdade'), findsOneWidget);
    });

    testWidgets('resolve o controller do escopo ativo via inject', (
      tester,
    ) async {
      when(
        () => mockController.state,
      ).thenReturn(const SuccessState<String>('injetado'));

      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: TestModulePage())),
      );

      expect(const TestModulePage().controller, same(mockController));
      expect(find.text('Sucesso: injetado'), findsOneWidget);
    });
  });
}
