import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/src/view_state.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

void main() {
  group('ViewState', () {
    test('InitialState instanciável', () {
      const state = InitialState<String>();
      expect(state, isA<ViewState<String>>());
    });

    test('LoadingState instanciável', () {
      const state = LoadingState<String>();
      expect(state, isA<ViewState<String>>());
    });

    test('SuccessState carrega os dados informados', () {
      const state = SuccessState<String>('meus_dados');
      expect(state.data, 'meus_dados');
    });

    test('ErrorState carrega o erro informado', () {
      const error = ErrorGeneric('Falha');
      const state = ErrorState<String>(error);
      expect(state.error, equals(error));
      expect(state.error.message, 'Falha');
    });
  });
}
