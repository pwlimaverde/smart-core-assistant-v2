import 'package:api_client/api_client.dart';
import 'package:api_client/grpc_web_client.dart';
import 'package:app_config/app_config.dart';
import 'package:core_module/core_module.dart' as core;
import 'package:get_it_module/get_it_module.dart';

import 'features/login/data/datasources/login_grpc_datasource.dart';
import 'features/login/data/datasources/logout_grpc_datasource.dart';
import 'features/login/data/datasources/refresh_grpc_datasource.dart';
import 'features/login/data/datasources/secure_local_storage_service.dart';
import 'features/login/data/datasources/token_local_datasource.dart';
import 'features/login/data/services/auth_service_impl.dart';
import 'features/login/domain/services/auth_service.dart';
import 'features/login/presentation/routes/login_route.dart';

/// Módulo de login: registra as implementações reais de auth/storage no escopo
/// global (substituindo os NoOps que o InfraModule deixou de registrar) e
/// contribui com a rota '/login'.
///
/// O `AuthServiceImpl` é registrado **uma vez** e exposto sob os dois contratos:
/// o rico ([AuthService] deste módulo) e o fino (`core.AuthService`, gancho de
/// boot `checkCurrentUser`).
final class LoginModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Cliente gRPC-Web real (borda do browser) — o access token vem do
    // SessionService (memória). Fica no módulo de borda, não no core_module.
    i.lazySingleton<ApiClient>(
      () => GrpcApiClient(
        endpoint: inject<AppConfig>().apiEndpoint,
        readAccessToken: () async => inject<core.SessionService>().token,
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

    // Serviço de auth real (instância única para os dois contratos).
    i.lazySingleton<AuthServiceImpl>(() {
      final authClient = (inject<ApiClient>() as GrpcApiClient).auth;
      return AuthServiceImpl(
        loginDatasource: LoginGrpcDatasource(client: authClient),
        refreshDatasource: RefreshGrpcDatasource(client: authClient),
        logoutDatasource: LogoutGrpcDatasource(client: authClient),
        tokenStore: inject<TokenLocalDatasource>(),
        session: inject<core.SessionService>(),
      );
    });
    i.lazySingleton<AuthService>(() => inject<AuthServiceImpl>());
    i.lazySingleton<core.AuthService>(() => inject<AuthServiceImpl>());
  }

  @override
  List<GetItModule> routes() => [LoginRoute()];
}
