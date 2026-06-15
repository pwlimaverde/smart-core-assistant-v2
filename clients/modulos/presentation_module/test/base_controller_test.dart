import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

// Controller concreto mínimo para teste
final class _TestController extends BaseController<String> {
  Future<void> load(ReturnSuccessOrError<String> result) =>
      execute(() async => result);
}

void main() {
  group('BaseController.execute', () {
    blocTest<_TestController, ViewState<String>>(
      'emite [Loading, Success] para SuccessReturn',
      build: _TestController.new,
      act: (c) => c.load(const SuccessReturn(success: 'dado')),
      expect: () => [
        isA<LoadingState<String>>(),
        isA<SuccessState<String>>().having((s) => s.data, 'data', 'dado'),
      ],
    );

    blocTest<_TestController, ViewState<String>>(
      'emite [Loading, Error] para ErrorReturn',
      build: _TestController.new,
      act: (c) =>
          c.load(const ErrorReturn(error: ErrorGeneric(message: 'falhou'))),
      expect: () => [
        isA<LoadingState<String>>(),
        isA<ErrorState<String>>().having(
          (s) => s.error.message,
          'message',
          'falhou',
        ),
      ],
    );
  });
}
