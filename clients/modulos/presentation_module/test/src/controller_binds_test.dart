import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:presentation_module/src/controller_binds.dart';

class _MyTestCubit extends Cubit<int> {
  _MyTestCubit() : super(0);
}

void main() {
  final getIt = GetIt.instance;

  group('ControllerBinds Extension', () {
    tearDown(() {
      getIt.reset();
    });

    test('registra controller como lazySingleton e invoca dispose', () async {
      final injector = Injector(getIt);
      injector.controller<_MyTestCubit>(() => _MyTestCubit());

      expect(getIt.isRegistered<_MyTestCubit>(), isTrue);

      final cubit = getIt<_MyTestCubit>();
      expect(cubit.state, 0);

      // Descarta o singleton e valida que o Cubit foi fechado (close chamado)
      await getIt.resetLazySingleton<_MyTestCubit>(instance: cubit);
      expect(cubit.isClosed, isTrue);
    });
  });
}
