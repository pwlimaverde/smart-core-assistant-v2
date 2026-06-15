import 'package:dependencies_module/dependencies_module.dart';

import 'presentation/routes/initial_loading_route.dart';

/// Módulo de bootstrap — contribui apenas com a rota '/'.
///
/// Não registra serviços globais; o InfraModule cuida da infra.
final class InitialLoadingModule extends AppModule {
  @override
  List<GetItModule> routes() => [InitialLoadingRoute()];
}
