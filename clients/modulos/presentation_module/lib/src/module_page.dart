import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import 'base_controller.dart';
import 'view_state.dart';

/// Página base para telas "um controller, um estado".
///
/// Resolve o controller via [inject], escuta o [ViewState] e renderiza o
/// método correspondente. A subclasse implementa apenas [onSuccess]; os demais
/// estados têm defaults sobrescrevíveis. [onInit] é um gancho de ciclo de vida
/// chamado UMA vez na montagem (ex.: disparar a carga inicial / bootstrap).
abstract class ModulePage<C extends BaseController<T>, T>
    extends StatefulWidget {
  const ModulePage({super.key});

  /// Controller resolvido do escopo ativo (feature → global).
  C get controller => inject<C>();

  /// Chamado uma vez quando a página é montada. Padrão: nada.
  void onInit(BuildContext context) {}

  /// Estado inicial (default: vazio).
  Widget onInitial(BuildContext context) => const SizedBox.shrink();

  /// Carregando (default: spinner centralizado).
  Widget onLoading(BuildContext context) =>
      const Center(child: CircularProgressIndicator());

  /// Erro (default: mensagem do AppError centralizada).
  Widget onError(BuildContext context, AppError error) =>
      Center(child: Text(error.message));

  /// Sucesso — único método obrigatório.
  Widget onSuccess(BuildContext context, T data);

  @override
  State<ModulePage<C, T>> createState() => _ModulePageState<C, T>();
}

class _ModulePageState<C extends BaseController<T>, T>
    extends State<ModulePage<C, T>> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onInit(context));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<C, ViewState<T>>(
      bloc: widget.controller,
      builder: (context, state) => switch (state) {
        InitialState<T>() => widget.onInitial(context),
        LoadingState<T>() => widget.onLoading(context),
        ErrorState<T>(:final error) => widget.onError(context, error),
        SuccessState<T>(:final data) => widget.onSuccess(context, data),
      },
    );
  }
}
