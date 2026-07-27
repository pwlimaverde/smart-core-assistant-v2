import 'package:bloc/bloc.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'view_state.dart';

/// Base de todos os controllers de tela.
///
/// É um `Cubit<ViewState<T>>` que começa em [InitialState]. O método [execute]
/// elimina o boilerplate de try/catch/emit: roda uma tarefa que devolve
/// [ReturnSuccessOrError] e mapeia o resultado para os estados.
abstract class BaseController<T> extends Cubit<ViewState<T>> {
  BaseController() : super(InitialState<T>());

  /// Emite [LoadingState], executa [task] e mapeia o resultado:
  ///  - [Success] → [SuccessState];
  ///  - [Failure] → [ErrorState] (carregando o erro como [AppError]).
  ///
  /// O `switch` é exaustivo sobre o tipo selado — a lib não expõe
  /// `fold`/`getOrElse`/`isSuccess`, e o pattern matching é a única forma de
  /// recuperar o valor.
  ///
  /// [E] é o conjunto **fechado** de erros da feature (`sealed class … extends
  /// AppError`), parametrizado **por chamada** e não por controller: o mesmo
  /// controller costuma orquestrar usecases de features vizinhas, com conjuntos
  /// de erro diferentes. A exaustividade sobre [E] vale onde há decisão de
  /// negócio; aqui, no caminho para a tela, o erro é degradado para [AppError] —
  /// que é tudo de que [ErrorState] precisa, uma mensagem. Isso evita contaminar
  /// [ViewState], `ModulePage` e `ViewStateBuilder` com um segundo parâmetro de
  /// tipo que a árvore de widgets inteira teria de carregar.
  Future<void> execute<E extends AppError>(
    Future<ReturnSuccessOrError<T, E>> Function() task,
  ) async {
    emit(LoadingState<T>());
    switch (await task()) {
      case Success(:final value):
        emit(SuccessState<T>(value));
      case Failure(:final error):
        emit(ErrorState<T>(error));
    }
  }
}
