import 'package:dependencies_module/dependencies_module.dart';

import 'features/config/data/datasources/config_datasources.dart';
import 'features/config/data/repositories/config_repositories.dart';
import 'features/config/domain/usecases/config_usecases.dart';
import 'features/config/presentation/routes/tenant_own_config_route.dart';
import 'features/convites/data/datasources/convites_datasources.dart';
import 'features/convites/data/repositories/convites_repositories.dart';
import 'features/convites/domain/usecases/convites_usecases.dart';
import 'features/convites/presentation/routes/accept_invite_route.dart';
import 'features/convites/presentation/routes/invites_route.dart';
import 'features/usuarios/data/datasources/usuarios_datasources.dart';
import 'features/usuarios/data/repositories/usuarios_repositories.dart';
import 'features/usuarios/domain/usecases/usuarios_usecases.dart';
import 'features/usuarios/presentation/routes/tenant_users_route.dart';

/// Módulo do painel do tenant (N3), em três features: **convites**,
/// **usuarios** (papéis e `flow_permissions`) e **config** (persona do bot,
/// modelos de IA, chaves de API).
///
/// Reusa o `AdminServiceClient` gRPC-Web já exposto pelo `GrpcApiClient` global —
/// os RPCs daqui são tenant-scoped (guard `exigir_autenticado_do_metadata`, não
/// superuser), e nenhum deles recebe `tenant_id`: o servidor o resolve a partir
/// da sessão.
///
/// A cadeia de cada operação (`Datasource → Repository → Usecase`) é montada
/// aqui. O `TenantAdminService` de 8 métodos e o `TenantAdminServiceImpl` que
/// repetia o mesmo `try/catch` oito vezes deixaram de existir.
final class TenantModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // ── convites ──────────────────────────────────────────────────────────
    i.lazySingleton<CreateInviteUsecase>(
      () => CreateInviteUsecase(
        repository: CreateInviteRepository(
          datasource: CreateInviteDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<ListInvitesUsecase>(
      () => ListInvitesUsecase(
        repository: ListInvitesRepository(
          datasource: ListInvitesDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<RevokeInviteUsecase>(
      () => RevokeInviteUsecase(
        repository: RevokeInviteRepository(
          datasource: RevokeInviteDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<AcceptInviteUsecase>(
      () => AcceptInviteUsecase(
        repository: AcceptInviteRepository(
          datasource: AcceptInviteDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── usuarios ──────────────────────────────────────────────────────────
    i.lazySingleton<ListTenantUsersUsecase>(
      () => ListTenantUsersUsecase(
        repository: ListTenantUsersRepository(
          datasource: ListTenantUsersDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<UpdateTenantUserUsecase>(
      () => UpdateTenantUserUsecase(
        repository: UpdateTenantUserRepository(
          datasource: UpdateTenantUserDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── config ────────────────────────────────────────────────────────────
    i.lazySingleton<GetMyTenantConfigUsecase>(
      () => GetMyTenantConfigUsecase(
        repository: GetMyTenantConfigRepository(
          datasource: GetMyTenantConfigDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<UpdateMyTenantConfigUsecase>(
      () => UpdateMyTenantConfigUsecase(
        repository: UpdateMyTenantConfigRepository(
          datasource: UpdateMyTenantConfigDatasource(client: _adminClient()),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() => [
    AcceptInviteRoute(),
    InvitesRoute(),
    TenantUsersRoute(),
    TenantOwnConfigRoute(),
  ];

  /// Stub gRPC do admin, extraído do `ApiClient` global da plataforma.
  static AdminServiceClient _adminClient() {
    final client = inject<ApiClient>();
    if (client is! GrpcTransport) {
      throw StateError('ApiClient não é do tipo GrpcTransport esperado.');
    }
    return client.admin;
  }
}
