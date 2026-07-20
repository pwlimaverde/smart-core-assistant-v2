import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:initial_loading_module/src/presentation/controllers/initial_loading_controller.dart';
import 'package:initial_loading_module/src/presentation/pages/initial_loading_page.dart';
import 'package:initial_loading_module/src/presentation/routes/initial_loading_route.dart';

void main() {
  tearDown(() => GetIt.instance.reset());

  test('path é "/"', () {
    expect(InitialLoadingRoute().path, '/');
  });

  test('page é InitialLoadingPage', () {
    expect(InitialLoadingRoute().page, isA<InitialLoadingPage>());
  });

  test('binds registra o InitialLoadingController com os módulos e o '
      'BootState resolvidos do escopo', () {
    final modules = <AppModule>[];
    final bootState = BootState();
    GetIt.instance.registerSingleton<List<AppModule>>(modules);
    GetIt.instance.registerSingleton<BootState>(bootState);

    InitialLoadingRoute().binds(Injector(GetIt.instance));

    final controller = inject<InitialLoadingController>();
    expect(controller.modules, same(modules));
    expect(controller.bootState, same(bootState));
  });
}
