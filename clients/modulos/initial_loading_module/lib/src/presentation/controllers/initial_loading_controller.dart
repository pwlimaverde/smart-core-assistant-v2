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

  Future<void> bootstrap() => execute(() async {
    await runBootTasks(modules);
    bootState.complete();
    return const SuccessReturn(success: null);
  });
}
