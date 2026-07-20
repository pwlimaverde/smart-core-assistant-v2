import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:get_it_module/get_it_module.dart';
import 'package:get_it_module/src/get_it_module_scope.dart';

// Serviço fictício exclusivo da rota, registrado só dentro do escopo.
abstract interface class _ScopedService {}

final class _ScopedServiceImpl implements _ScopedService {}

// Módulo fake que registra um serviço de escopo e expõe uma página simples.
final class _FakeScopedModule extends GetItModule {
  int bindsCalls = 0;

  @override
  String get path => '/scoped';

  @override
  Widget get page => const Text('conteúdo da rota', textDirection: TextDirection.ltr);

  @override
  void binds(Injector i) {
    bindsCalls++;
    i.singleton<_ScopedService>(_ScopedServiceImpl());
  }
}

void main() {
  tearDown(() => GetIt.instance.reset());

  testWidgets(
    'ao montar, empilha um novo escopo e roda os binds do módulo (serviço '
    'fica resolvível); ao desmontar, descarta exatamente esse escopo',
    (tester) async {
      final module = _FakeScopedModule();

      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: GetItModuleScope(module: module),
        ),
      );

      expect(module.bindsCalls, 1);
      expect(find.text('conteúdo da rota'), findsOneWidget);
      expect(GetIt.instance.isRegistered<_ScopedService>(), isTrue);

      // Desmonta o widget: o escopo (e o que foi registrado nele) some.
      await tester.pumpWidget(const SizedBox.shrink());

      expect(GetIt.instance.isRegistered<_ScopedService>(), isFalse);
    },
  );

  testWidgets('cada montagem gera um escopo com nome único (não colide '
      'entre instâncias do mesmo módulo)', (tester) async {
    final moduleA = _FakeScopedModule();
    final moduleB = _FakeScopedModule();

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GetItModuleScope(module: moduleA),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: GetItModuleScope(module: moduleB),
      ),
    );

    // O segundo binds ainda funciona normalmente após o primeiro escopo ter
    // sido descartado (nomes de escopo não colidiram).
    expect(moduleA.bindsCalls, 1);
    expect(moduleB.bindsCalls, 1);
    expect(GetIt.instance.isRegistered<_ScopedService>(), isTrue);
  });
}
