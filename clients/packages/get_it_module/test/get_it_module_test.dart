import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:get_it_module/get_it_module.dart';

// Serviço fictício para os testes
abstract interface class _FakeService {
  String get value;
}

final class _FakeServiceImpl implements _FakeService {
  @override
  String get value => 'ok';
}

// Módulo de teste que registra o serviço global
final class _TestModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    i.singleton<_FakeService>(_FakeServiceImpl());
  }
}

// Módulo com bootTasks em dois estágios
final class _BootModule extends AppModule {
  final List<String> log;
  _BootModule(this.log);

  @override
  List<BootTask> bootTasks() => [
    BootTask(BootStage.infra, () async => log.add('infra')),
    BootTask(BootStage.session, () async => log.add('session')),
  ];
}

void main() {
  tearDown(() => GetIt.instance.reset());

  test('installModules registra serviço global resolvível via inject', () {
    installModules([_TestModule()]);
    expect(inject<_FakeService>().value, 'ok');
  });

  test('runBootTasks executa estágio infra antes de session', () async {
    final log = <String>[];
    await runBootTasks([_BootModule(log)]);
    expect(log, ['infra', 'session']);
  });
}
