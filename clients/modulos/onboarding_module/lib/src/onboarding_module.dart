import 'package:api_client/api_client.dart';
import 'package:get_it_module/get_it_module.dart';

import 'features/cadastro/data/datasources/cadastro_datasources.dart';
import 'features/cadastro/data/repositories/cadastro_repositories.dart';
import 'features/cadastro/domain/services/cadastro_sessao.dart';
import 'features/cadastro/domain/usecases/cadastro_usecases.dart';
import 'features/cadastro/presentation/routes/cadastro_routes.dart';

/// Wizard público de cadastro de tenant.
///
/// Monta as sete cadeias Datasource → Repository → Usecase e contribui com as
/// quatro rotas do wizard. Depende do `login_module` já estar composto: o passo
/// final entra na conta recém-criada pelo `AuthService` dele.
final class OnboardingModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Estado do cadastro em andamento — singleton porque atravessa as rotas.
    i.lazySingleton<CadastroSessao>(() => CadastroSessao());

    i.lazySingleton<VerificarSlugUsecase>(
      () => VerificarSlugUsecase(
        repository: VerificarSlugRepository(
          datasource: VerificarSlugDatasource(client: _client()),
        ),
      ),
    );
    i.lazySingleton<ListarPlanosUsecase>(
      () => ListarPlanosUsecase(
        repository: ListarPlanosRepository(
          datasource: ListarPlanosDatasource(client: _client()),
        ),
      ),
    );
    i.lazySingleton<ListarProvedoresUsecase>(
      () => ListarProvedoresUsecase(
        repository: ListarProvedoresRepository(
          datasource: ListarProvedoresDatasource(client: _client()),
        ),
      ),
    );
    i.lazySingleton<IniciarCadastroUsecase>(
      () => IniciarCadastroUsecase(
        repository: IniciarCadastroRepository(
          datasource: IniciarCadastroDatasource(client: _client()),
        ),
      ),
    );
    i.lazySingleton<SelecionarPlanoUsecase>(
      () => SelecionarPlanoUsecase(
        repository: SelecionarPlanoRepository(
          datasource: SelecionarPlanoDatasource(client: _client()),
        ),
      ),
    );
    i.lazySingleton<ConfirmarPagamentoUsecase>(
      () => ConfirmarPagamentoUsecase(
        repository: ConfirmarPagamentoRepository(
          datasource: ConfirmarPagamentoDatasource(client: _client()),
        ),
      ),
    );
    i.lazySingleton<StatusCadastroUsecase>(
      () => StatusCadastroUsecase(
        repository: StatusCadastroRepository(
          datasource: StatusCadastroDatasource(client: _client()),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() => [
        CadastroDadosRoute(),
        CadastroPlanoRoute(),
        CadastroPagamentoRoute(),
        CadastroProntoRoute(),
      ];

  /// Stub gRPC do cadastro, extraído do `ApiClient` global da plataforma.
  /// Diferente dos demais, este **não** leva interceptor de token: o cadastro
  /// acontece antes de existir sessão.
  static OnboardingServiceClient _client() =>
      (inject<ApiClient>() as GrpcTransport).onboarding;
}
