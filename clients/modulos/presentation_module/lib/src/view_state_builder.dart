import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'base_controller.dart';
import 'view_state.dart';

/// Renderiza o [ViewState] de um controller em qualquer ponto da árvore
/// (ex.: dentro de um Scaffold próprio, com AppBar e várias regiões).
///
/// Resolve o controller via [inject] por padrão, ou usa um [controller]
/// explícito. Todos os estados, exceto [onSuccess], têm defaults.
class ViewStateBuilder<C extends BaseController<T>, T> extends StatelessWidget {
  final C? controller;
  final WidgetBuilder? onInitial;
  final WidgetBuilder? onLoading;
  final Widget Function(BuildContext context, AppError error)? onError;
  final Widget Function(BuildContext context, T data) onSuccess;

  const ViewStateBuilder({
    super.key,
    required this.onSuccess,
    this.controller,
    this.onInitial,
    this.onLoading,
    this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller ?? inject<C>();
    return BlocBuilder<C, ViewState<T>>(
      bloc: c,
      builder: (context, state) => switch (state) {
        InitialState<T>() =>
          onInitial?.call(context) ?? const SizedBox.shrink(),
        LoadingState<T>() =>
          onLoading?.call(context) ??
              const Center(child: CircularProgressIndicator()),
        ErrorState<T>(:final error) =>
          onError?.call(context, error) ?? Center(child: Text(error.message)),
        SuccessState<T>(:final data) => onSuccess(context, data),
      },
    );
  }
}
