import 'package:api_client/api_client.dart';
import 'package:get_it_module/get_it_module.dart';

import 'features/cadastro/data/datasources/cadastro_datasources.dart';
import 'features/cadastro/data/repositories/cadastro_repositories.dart';
import 'features/cadastro/domain/services/cadastro_sessao.dart';
import 'features/cadastro/domain/usecases/cadastro_usecases.dart';
import 'features/cadastro/presentation/routes/cadastro_routes.dart';
import 'features/configuracao/data/datasources/configuracao_datasources.dart';
import 'features/configuracao/data/repositories/configuracao_repositories.dart';
import 'features/configuracao/domain/usecases/configuracao_usecases.dart';
import 'features/configuracao/presentation/routes/configuracao_routes.dart';

/// Wizard de entrada do tenant: criar a conta e deixar o sistema operando.
///
/// Duas trilhas de quatro telas. A primeira (`/cadastro`) é **pública** — quem
/// a percorre ainda não tem conta. A segunda (`/configuracao`) roda **com
/// sessão**, logo depois do primeiro login, e é o que tira o tenant de "conta
/// criada" para "atendimento funcionando".
///
/// Depende do `login_module` já estar composto: o fim do cadastro entra na
/// conta recém-criada pelo `AuthService` dele.
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

    // --- Configuração inicial guiada (com sessão) ---
    //
    // Usa o `AdminServiceClient`, que leva o token no interceptor: aqui o
    // tenant já entrou, e o servidor tira o `tenant_id` das claims.
    i.lazySingleton<CriarConexaoUsecase>(
      () => CriarConexaoUsecase(
        repository: CriarConexaoRepository(
          datasource: CriarConexaoDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<EstadoConexaoUsecase>(
      () => EstadoConexaoUsecase(
        repository: EstadoConexaoRepository(
          datasource: EstadoConexaoDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<CriarDepartamentoUsecase>(
      () => CriarDepartamentoUsecase(
        repository: CriarDepartamentoRepository(
          datasource: CriarDepartamentoDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<DefinirPersonaUsecase>(
      () => DefinirPersonaUsecase(
        repository: DefinirPersonaRepository(
          datasource: DefinirPersonaDatasource(client: _admin()),
        ),
      ),
    );
    i.lazySingleton<ProgressoUsecase>(
      () => ProgressoUsecase(
        repository: ProgressoRepository(
          datasource: ProgressoDatasource(client: _admin()),
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
        ConexaoWhatsappRoute(),
        DepartamentoRoute(),
        AssistenteRoute(),
        ConfiguracaoProntaRoute(),
      ];

  /// Stub gRPC do cadastro, extraído do `ApiClient` global da plataforma.
  /// Diferente dos demais, este **não** leva interceptor de token: o cadastro
  /// acontece antes de existir sessão.
  static OnboardingServiceClient _client() =>
      (inject<ApiClient>() as GrpcTransport).onboarding;

  /// Stub autenticado, para a configuração guiada (já há sessão).
  static AdminServiceClient _admin() =>
      (inject<ApiClient>() as GrpcTransport).admin;
}
