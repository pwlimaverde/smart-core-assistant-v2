import 'dart:async';

import 'package:dependencies_module/dependencies_module.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:initial_loading_module/src/presentation/controllers/initial_loading_controller.dart';
import 'package:initial_loading_module/src/presentation/pages/initial_loading_page.dart';

// InitialLoadingController é uma classe `final` — não pode ser mockada via
// mocktail/MockCubit (implements exigiria estender fora da própria lib).
// Por isso os testes usam a instância real do controller: para o fluxo
// completo, um módulo cujo bootTask é controlado por um Completer; para os
// `on*` isolados, chamamos os overrides da página diretamente com um
// BuildContext válido — exercita exatamente o código de produção sem
// depender do BlocBuilder.
final class _ControllableModule extends AppModule {
  final Future<void> gate;
  _ControllableModule(this.gate);

  @override
  List<BootTask> bootTasks() => [BootTask(BootStage.infra, () => gate)];
}

void main() {
  final getIt = GetIt.instance;

  tearDown(() => getIt.reset());

  testWidgets(
    'fluxo real: monta em Loading e evolui para Success ao concluir o boot',
    (tester) async {
      final completer = Completer<void>();
      final bootState = BootState();
      getIt.registerSingleton<InitialLoadingController>(
        InitialLoadingController(
          modules: [_ControllableModule(completer.future)],
          bootState: bootState,
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: InitialLoadingPage()));
      await tester
          .pump(); // postFrameCallback -> onInit -> bootstrap() -> Loading

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(bootState.value, isFalse);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(bootState.value, isTrue);
    },
  );

  testWidgets('onLoading renderiza spinner centralizado num Scaffold', (
    tester,
  ) async {
    const page = InitialLoadingPage();
    late BuildContext ctx;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: page.onLoading(ctx)));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('onSuccess não renderiza nenhum conteúdo visível', (
    tester,
  ) async {
    const page = InitialLoadingPage();
    late BuildContext ctx;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    await tester.pumpWidget(MaterialApp(home: page.onSuccess(ctx, null)));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets(
    'onError renderiza a mensagem do AppError e o retry chama bootstrap() '
    'de novo no controller real',
    (tester) async {
      final bootState = BootState();
      getIt.registerSingleton<InitialLoadingController>(
        InitialLoadingController(modules: const [], bootState: bootState),
      );
      const page = InitialLoadingPage();
      late BuildContext ctx;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      final errorWidget = page.onError(
        ctx,
        const ErrorGeneric('falha no boot'),
      );
      await tester.pumpWidget(MaterialApp(home: errorWidget));

      expect(find.text('falha no boot'), findsOneWidget);
      expect(find.text('Tentar novamente'), findsOneWidget);
      expect(bootState.value, isFalse);

      // Sem bootTasks registrados, um novo bootstrap() conclui com sucesso e
      // completa o BootState — prova que o retry chama o controller real.
      await tester.tap(find.text('Tentar novamente'));
      await tester.pumpAndSettle();

      expect(bootState.value, isTrue);
    },
  );
}
