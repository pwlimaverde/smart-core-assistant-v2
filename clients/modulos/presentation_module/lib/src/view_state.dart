import 'package:return_success_or_error/return_success_or_error.dart';

/// Estado genérico de uma tela gerenciada por um BaseController.
///
/// Toda tela do monorepo usa este modelo selado. Quando uma tela tem vários
/// pedaços de estado, [T] deve ser um view-model composto (record ou classe
/// imutável) — não se cria um sealed state por feature.
sealed class ViewState<T> {
  const ViewState();
}

/// Estado inicial, antes de qualquer ação.
final class InitialState<T> extends ViewState<T> {
  const InitialState();
}

/// Operação em andamento.
final class LoadingState<T> extends ViewState<T> {
  const LoadingState();
}

/// Operação concluída com sucesso, carregando o dado [data].
final class SuccessState<T> extends ViewState<T> {
  final T data;
  const SuccessState(this.data);
}

/// Operação falhou, carregando o [AppError] do return_success_or_error.
final class ErrorState<T> extends ViewState<T> {
  final AppError error;
  const ErrorState(this.error);
}
