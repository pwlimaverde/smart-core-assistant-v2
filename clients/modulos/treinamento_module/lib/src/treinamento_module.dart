import 'package:api_client/api_client.dart';
import 'package:get_it_module/get_it_module.dart';

import 'features/treinamento/data/datasources/treinamento_datasources.dart';
import 'features/treinamento/data/repositories/treinamento_repositories.dart';
import 'features/treinamento/domain/usecases/treinamento_usecases.dart';
import 'features/treinamento/presentation/routes/treinamento_routes.dart';

/// Treinamento da IA: o material que o assistente usa para responder.
///
/// Existe porque a fundação estava pronta e sem caminho — o banco tinha as
/// tabelas e o servidor a camada de acesso, mas não havia RPC nem tela. Treinar
/// o assistente é a razão de ser do produto, e não dava para fazer pelo sistema.
///
/// Roda **com sessão de tenant**: as rotas ficam sob `/tenant/`, que o guard do
/// app protege com `tenant:admin`.
final class TreinamentoModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    i.lazySingleton<ListarTreinamentosUsecase>(
      () => ListarTreinamentosUsecase(
        repository: ListarTreinamentosRepository(
          datasource: ListarTreinamentosDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<CriarTreinamentoUsecase>(
      () => CriarTreinamentoUsecase(
        repository: CriarTreinamentoRepository(
          datasource: CriarTreinamentoDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<ObterTreinamentoUsecase>(
      () => ObterTreinamentoUsecase(
        repository: ObterTreinamentoRepository(
          datasource: ObterTreinamentoDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<FinalizarTreinamentoUsecase>(
      () => FinalizarTreinamentoUsecase(
        repository: FinalizarTreinamentoRepository(
          datasource: FinalizarTreinamentoDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<RemoverTreinamentoUsecase>(
      () => RemoverTreinamentoUsecase(
        repository: RemoverTreinamentoRepository(
          datasource: RemoverTreinamentoDatasource(client: _admin()),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() => [TreinamentoRoute()];

  /// Stub autenticado — o treinamento é do tenant logado.
  static AdminServiceClient _admin() =>
      (inject<ApiClient>() as GrpcTransport).admin;
}
