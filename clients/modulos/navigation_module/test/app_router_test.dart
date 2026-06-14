import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:navigation_module/navigation_module.dart';

// Rota fake para teste
final class _FakeRoute extends GetItModule {
  @override
  String get path => '/fake';

  @override
  Widget get page => const SizedBox.shrink();

  @override
  void binds(Injector i) {}
}

void main() {
  test('AppRouter.build contém a rota do GetItModule fake', () {
    final router = AppRouter(
      initialLocation: '/fake',
      routes: [_FakeRoute()],
    ).build();

    final routePaths = router.configuration.routes
        .whereType<GoRoute>()
        .map((r) => r.path)
        .toList();

    expect(routePaths, contains('/fake'));
  });
}
