import 'package:api_client/api_client.dart';
import 'package:app_config/app_config.dart';
import 'package:core_module/core_module.dart' as core;
import 'package:get_it_module/get_it_module.dart';

import 'platform/api_client_factory.dart';
import 'features/login/data/datasources/login_grpc_datasource.dart';
import 'features/login/data/datasources/logout_grpc_datasource.dart';
import 'features/login/data/datasources/refresh_grpc_datasource.dart';
import 'features/login/data/datasources/secure_local_storage_service.dart';
import 'features/login/data/datasources/token_local_datasource.dart';
import 'features/login/data/repositories/login_repository.dart';
import 'features/login/data/repositories/logout_repository.dart';
import 'features/login/data/repositories/refresh_repository.dart';
import 'features/login/data/services/auth_service_impl.dart';
import 'features/login/domain/services/auth_service.dart';
import 'features/login/domain/usecases/login_usecase.dart';
import 'features/login/domain/usecases/logout_usecase.dart';
import 'features/login/domain/usecases/refresh_token_usecase.dart';
import 'features/login/presentation/routes/login_route.dart';
import 'features/recuperacao_senha/data/datasources/recuperacao_datasources.dart';
import 'features/recuperacao_senha/data/repositories/recuperacao_repositories.dart';
import 'features/recuperacao_senha/domain/usecases/recuperacao_usecases.dart';
import 'features/recuperacao_senha/presentation/routes/recuperacao_routes.dart';

/// Módulo de login: registra as implementações reais de auth/storage no escopo
/// global (substituindo os NoOps que o InfraModule deixou de registrar) e
/// contribui com a rota '/login'.
///
/// O `AuthServiceImpl` é registrado **uma vez** e exposto sob os dois contratos:
/// o rico ([AuthService] deste módulo) e o fino (`core.AuthService`, gancho de
/// boot `checkCurrentUser`).
final class LoginModule extends AppModule {
  /// Rota do autocadastro, quando o app a tem.
  ///
  /// O app do tenant passa `/cadastro`: quem instalou o programa no próprio
  /// computador precisa de um caminho visível para criar a conta, já que num
  /// app de desktop não há URL para digitar. O painel do superusuário não passa
  /// nada — lá não existe autocadastro.
  final String? rotaDeCadastro;

  LoginModule({this.rotaDeCadastro});

  @override
  void globalBinds(Injector i) {
    // Cliente gRPC real da plataforma (gRPC-Web no browser, sockets HTTP/2 no
    // desktop) — escolhido por import condicional na factory. O access token vem
    // do SessionService (memória). Fica no módulo de borda, não no core_module.
    i.lazySingleton<ApiClient>(
      () => createPlatformApiClient(
        endpoint: inject<AppConfig>().apiEndpoint,
        // Pelo `AuthService`, não pelo `SessionService`: é o caminho que
        // renova o token vencendo antes de a chamada sair. Lendo o
        // `SessionService` cru — como era —, o access vencia e o app passava a
        // responder "sessão expirada" a tudo, com o refresh guardado e válido
        // ali do lado, sem ninguém para usá-lo.
        //
        // `inject` acontece a cada chamada, não na construção: o `AuthService`
        // depende deste mesmo `ApiClient`, e resolvê-lo agora fecharia um
        // ciclo.
        readAccessToken: () => inject<AuthService>().accessTokenParaChamada(),
        enableLogging: inject<AppConfig>().enableLogging,
      ),
    );

    // Storage real (secure storage) — substitui o LocalStorageServiceNoOp.
    i.lazySingleton<core.LocalStorageService>(
      () => SecureLocalStorageService(),
    );
    i.lazySingleton<TokenLocalDatasource>(
      () => TokenLocalDatasource(storage: inject<core.LocalStorageService>()),
    );

    // Usecases da feature: cada um recebe o repositório, que recebe o
    // datasource — a cadeia Datasource -> Repository -> Usecase da v3, montada
    // aqui em vez de dentro do serviço.
    i.lazySingleton<LoginUsecase>(
      () => LoginUsecase(
        repository: LoginRepository(
          datasource: LoginGrpcDatasource(client: _authClient()),
        ),
      ),
    );
    i.lazySingleton<RefreshTokenUsecase>(
      () => RefreshTokenUsecase(
        repository: RefreshRepository(
          datasource: RefreshGrpcDatasource(client: _authClient()),
        ),
      ),
    );
    i.lazySingleton<LogoutUsecase>(
      () => LogoutUsecase(
        repository: LogoutRepository(
          datasource: LogoutGrpcDatasource(client: _authClient()),
        ),
      ),
    );

    // N11 E8 — recuperação de senha. Globais, e não no escopo das rotas,
    // porque as duas telas não têm controller: cada uma chama o seu usecase.
    i.lazySingleton<SolicitarRedefinicaoUsecase>(
      () => SolicitarRedefinicaoUsecase(
        repository: SolicitarRedefinicaoRepository(
          datasource: SolicitarRedefinicaoDatasource(client: _authClient()),
        ),
      ),
    );
    i.lazySingleton<RedefinirSenhaUsecase>(
      () => RedefinirSenhaUsecase(
        repository: RedefinirSenhaRepository(
          datasource: RedefinirSenhaDatasource(client: _authClient()),
        ),
      ),
    );

    // Serviço de auth real (instância única para os dois contratos).
    i.lazySingleton<AuthServiceImpl>(
      () => AuthServiceImpl(
        loginUsecase: inject<LoginUsecase>(),
        refreshUsecase: inject<RefreshTokenUsecase>(),
        logoutUsecase: inject<LogoutUsecase>(),
        tokenStore: inject<TokenLocalDatasource>(),
        session: inject<core.SessionService>(),
      ),
    );
    i.lazySingleton<AuthService>(() => inject<AuthServiceImpl>());
    i.lazySingleton<core.AuthService>(() => inject<AuthServiceImpl>());
  }

  @override
  List<GetItModule> routes() => [
    LoginRoute(rotaDeCadastro: rotaDeCadastro),
    RecuperarSenhaRoute(),
    RedefinirSenhaRoute(),
  ];

  /// Stub gRPC de auth, extraído do `ApiClient` global da plataforma.
  static AuthServiceClient _authClient() =>
      (inject<ApiClient>() as GrpcTransport).auth;
}
