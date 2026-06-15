import 'package:bloc/bloc.dart';
import 'package:get_it_module/get_it_module.dart';

/// Açúcar sintático sobre o Injector para registrar controllers.
extension ControllerBinds on Injector {
  /// Registra um controller (Cubit/Bloc) como lazySingleton no escopo do
  /// módulo, fechando-o automaticamente (`close()`) quando o escopo é
  /// descartado (pop da tela).
  void controller<C extends BlocBase>(C Function() create) {
    lazySingleton<C>(create, dispose: (c) => c.close());
  }
}
