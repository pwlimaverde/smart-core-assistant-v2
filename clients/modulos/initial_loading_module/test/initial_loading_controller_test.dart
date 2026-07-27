import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:initial_loading_module/initial_loading_module.dart';
import 'package:dependencies_module/dependencies_module.dart';

// Módulo fake com bootTask registrável
final class _FakeModule extends AppModule {
  final List<String> log;
  _FakeModule(this.log);

  @override
  List<BootTask> bootTasks() => [
    BootTask(BootStage.infra, () async => log.add('infra')),
  ];
}

// Módulo fake cujo bootTask sempre falha (simula erro de infra no boot).
final class _FailingModule extends AppModule {
  @override
  List<BootTask> bootTasks() => [
    BootTask(BootStage.infra, () async => throw Exception('falha no boot')),
  ];
}

void main() {
  late BootState bootState;
  late List<AppModule> modules;
  late List<String> log;

  setUp(() {
    GetIt.instance.reset();
    log = [];
    bootState = BootState();
    modules = [_FakeModule(log)];
  });

  tearDown(() => GetIt.instance.reset());

  blocTest<InitialLoadingController, ViewState<void>>(
    'bootstrap emite [Loading, Success] e chama BootState.complete()',
    build: () =>
        InitialLoadingController(modules: modules, bootState: bootState),
    act: (c) => c.bootstrap(),
    expect: () => [isA<LoadingState<void>>(), isA<SuccessState<void>>()],
    verify: (_) {
      expect(bootState.value, isTrue);
      expect(log, contains('infra'));
    },
  );

  blocTest<InitialLoadingController, ViewState<void>>(
    'bootstrap com bootTask que falha emite [Loading, Error] e mantém '
    'BootState=false (rotas continuam barradas)',
    build: () => InitialLoadingController(
      modules: [_FailingModule()],
      bootState: bootState,
    ),
    act: (c) => c.bootstrap(),
    // A exceção do estágio de boot é capturada e vira ErrorState. Antes ela
    // escapava do controller: o estado parava em Loading e a splash ficava com
    // o spinner girando para sempre, apesar de o próprio doc do controller
    // prometer ErrorState. A tela de erro com "Tentar novamente" só funciona
    // porque esse estado agora é emitido.
    expect: () => [isA<LoadingState<void>>(), isA<ErrorState<void>>()],
    verify: (_) {
      expect(bootState.value, isFalse);
    },
  );

  blocTest<InitialLoadingController, ViewState<void>>(
    'a mensagem exibida no erro de boot é genérica (sem detalhe da exceção)',
    build: () => InitialLoadingController(
      modules: [_FailingModule()],
      bootState: bootState,
    ),
    act: (c) => c.bootstrap(),
    expect: () => [
      isA<LoadingState<void>>(),
      isA<ErrorState<void>>().having(
        (s) => ErrorMessageMapper.map(s.error),
        'mensagem exibida',
        ErrorMessageMapper.mensagemGenerica,
      ),
    ],
  );
}
