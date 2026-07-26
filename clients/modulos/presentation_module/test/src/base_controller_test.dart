import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Conjunto fechado de erros de uma feature fictícia — o formato que todas as
/// features passam a usar na v3.
sealed class _TesteError extends AppError {
  const _TesteError(super.message);
}

final class _TesteRegra extends _TesteError {
  const _TesteRegra() : super('regra de negocio violada');
}

final class _TesteIndisponivel extends _TesteError with NetworkFailure {
  const _TesteIndisponivel() : super('servidor indisponivel');
}

final class _TestController extends BaseController<String> {
  Future<void> load(ReturnSuccessOrError<String, _TesteError> result) =>
      execute(() async => result);

  /// Prova que o genérico é por chamada: o mesmo controller executa uma tarefa
  /// cujo erro vem de outro conjunto fechado.
  Future<void> loadDeOutraFeature(
    ReturnSuccessOrError<String, ErrorGeneric> result,
  ) => execute(() async => result);
}

void main() {
  group('BaseController.execute', () {
    blocTest<_TestController, ViewState<String>>(
      'emite [Loading, Success] para Success',
      build: _TestController.new,
      act: (c) => c.load(const Success('dado')),
      expect: () => [
        isA<LoadingState<String>>(),
        isA<SuccessState<String>>().having((s) => s.data, 'data', 'dado'),
      ],
    );

    blocTest<_TestController, ViewState<String>>(
      'emite [Loading, Error] para Failure',
      build: _TestController.new,
      act: (c) => c.load(const Failure(_TesteRegra())),
      expect: () => [
        isA<LoadingState<String>>(),
        isA<ErrorState<String>>().having(
          (s) => s.error.message,
          'message',
          'regra de negocio violada',
        ),
      ],
    );

    blocTest<_TestController, ViewState<String>>(
      'preserva o caso concreto do erro, com o marcador, dentro do ErrorState',
      build: _TestController.new,
      act: (c) => c.load(const Failure(_TesteIndisponivel())),
      expect: () => [
        isA<LoadingState<String>>(),
        isA<ErrorState<String>>()
            .having((s) => s.error, 'erro concreto', isA<_TesteIndisponivel>())
            .having((s) => s.error, 'marcador', isA<NetworkFailure>()),
      ],
    );

    blocTest<_TestController, ViewState<String>>(
      'o mesmo controller aceita tarefas de conjuntos de erro diferentes',
      build: _TestController.new,
      act: (c) => c.loadDeOutraFeature(const Failure(ErrorGeneric('outra'))),
      expect: () => [
        isA<LoadingState<String>>(),
        isA<ErrorState<String>>().having(
          (s) => s.error,
          'erro',
          isA<ErrorGeneric>(),
        ),
      ],
    );

    blocTest<_TestController, ViewState<String>>(
      'parte de InitialState e não emite nada antes de execute',
      build: _TestController.new,
      expect: () => <ViewState<String>>[],
      verify: (c) => expect(c.state, isA<InitialState<String>>()),
    );
  });
}
