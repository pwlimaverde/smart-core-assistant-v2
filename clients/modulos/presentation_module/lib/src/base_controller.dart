import 'package:bloc/bloc.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'view_state.dart';

/// Base de todos os controllers de tela.
///
/// É um `Cubit<ViewState<T>>` que começa em [InitialState]. O método
/// [execute] elimina o boilerplate de try/catch/emit: roda um usecase que
/// retorna [ReturnSuccessOrError] e mapeia o resultado para os estados.
abstract class BaseController<T> extends Cubit<ViewState<T>> {
  BaseController() : super(InitialState<T>());

  /// Emite [LoadingState], executa [task] e mapeia o resultado:
  ///  - [SuccessReturn] → [SuccessState];
  ///  - [ErrorReturn]   → [ErrorState] (carregando o [AppError]).
  ///
  /// O mapeamento usa `switch` exaustivo sobre o tipo selado
  /// [ReturnSuccessOrError]. A lib (v2.0.0) não expõe `fold`/`getOrElse`/
  /// `isSuccess` — o pattern matching é a única forma de recuperar o valor.
  Future<void> execute(Future<ReturnSuccessOrError<T>> Function() task) async {
    emit(LoadingState<T>());
    final result = await task();
    switch (result) {
      case SuccessReturn<T>():
        emit(SuccessState<T>(result.result));
      case ErrorReturn<T>():
        emit(ErrorState<T>(result.result));
    }
  }
}
