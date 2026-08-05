import 'package:api_client/api_client.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it_module/get_it_module.dart';

import 'features/intents/data/datasources/intents_datasources.dart';
import 'features/intents/data/repositories/intents_repositories.dart';
import 'features/intents/domain/usecases/intents_usecases.dart';
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
  /// Menu lateral do app hospedeiro, repassado à tela.
  final Widget Function()? drawerBuilder;

  TreinamentoModule({this.drawerBuilder});

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

    // ── intenções (curadoria manual do RAG) ───────────────────────────────
    i.lazySingleton<ListarIntentsUsecase>(
      () => ListarIntentsUsecase(
        repository: ListarIntentsRepository(
          datasource: ListarIntentsDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<CriarIntentUsecase>(
      () => CriarIntentUsecase(
        repository: CriarIntentRepository(
          datasource: CriarIntentDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<AtualizarIntentUsecase>(
      () => AtualizarIntentUsecase(
        repository: AtualizarIntentRepository(
          datasource: AtualizarIntentDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<RemoverIntentUsecase>(
      () => RemoverIntentUsecase(
        repository: RemoverIntentRepository(
          datasource: RemoverIntentDatasource(client: _admin()),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() =>
      [TreinamentoRoute(drawerBuilder: drawerBuilder)];

  /// Stub autenticado — o treinamento é do tenant logado.
  static AdminServiceClient _admin() =>
      (inject<ApiClient>() as GrpcTransport).admin;
}
