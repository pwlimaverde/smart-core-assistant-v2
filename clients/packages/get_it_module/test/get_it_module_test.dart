import 'package:flutter/widgets.dart';
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

// Rota fake para testar collectRoutes e bootModules
final class _FakeRoute extends GetItModule {
  final String _path;
  _FakeRoute(this._path);

  @override
  String get path => _path;

  @override
  Widget get page => const SizedBox.shrink();

  @override
  void binds(Injector i) {}
}

// Módulo que contribui rotas ao app
final class _RouteModule extends AppModule {
  final List<GetItModule> _routes;
  _RouteModule(this._routes);

  @override
  List<GetItModule> routes() => _routes;
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

  test('Injector.factory cria nova instância a cada resolução', () {
    final injector = Injector(GetIt.instance);
    injector.factory<_FakeService>(() => _FakeServiceImpl());
    final a = inject<_FakeService>();
    final b = inject<_FakeService>();
    expect(identical(a, b), isFalse);
  });

  test('Injector.lazySingleton retorna a mesma instância', () {
    final injector = Injector(GetIt.instance);
    injector.lazySingleton<_FakeService>(() => _FakeServiceImpl());
    final a = inject<_FakeService>();
    final b = inject<_FakeService>();
    expect(identical(a, b), isTrue);
  });

  test('collectRoutes agrega rotas de múltiplos módulos', () {
    final routes = collectRoutes([
      _RouteModule([_FakeRoute('/a'), _FakeRoute('/b')]),
      _RouteModule([_FakeRoute('/c')]),
    ]);
    expect(routes, hasLength(3));
    expect(routes.map((r) => r.path), containsAll(['/a', '/b', '/c']));
  });

  test('bootModules instala módulos e executa bootTasks em ordem', () async {
    final log = <String>[];
    await bootModules([_BootModule(log)]);
    expect(log, ['infra', 'session']);
  });
}
