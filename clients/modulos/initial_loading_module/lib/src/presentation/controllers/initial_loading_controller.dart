import 'dart:developer' as developer;

import 'package:dependencies_module/dependencies_module.dart';

/// Controller da splash: roda o boot por estágios e libera a barreira.
///
/// Ao concluir com sucesso, chama [BootState.complete()], que dispara o
/// refreshListenable do GoRouter e reavalia o redirect — liberando a navegação.
/// Em caso de falha, emite [ErrorState], mantendo BootState=false e barrando rotas.
final class InitialLoadingController extends BaseController<void> {
  final List<AppModule> modules;
  final BootState bootState;

  InitialLoadingController({required this.modules, required this.bootState});

  /// O boot não tem conjunto de erro próprio: qualquer exceção de um estágio é
  /// um bug de inicialização, não uma falha prevista de negócio. Por isso o
  /// [ErrorGeneric] da lib — e o `ErrorMessageMapper` já garante que a tela
  /// mostre texto genérico, sem o detalhe técnico da exceção.
  Future<void> bootstrap() => execute<ErrorGeneric>(() async {
    try {
      await runBootTasks(modules);
      bootState.complete();
      return const Success(null);
    } catch (exception, stackTrace) {
      developer.log(
        'boot falhou',
        name: 'initial_loading_module',
        error: exception,
        stackTrace: stackTrace,
      );
      return const Failure(ErrorGeneric('falha ao inicializar o aplicativo'));
    }
  });
}
