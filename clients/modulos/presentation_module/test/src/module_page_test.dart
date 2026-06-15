import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';

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
  });
}
