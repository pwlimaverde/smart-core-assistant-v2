import 'package:api_client/grpc_web_client.dart';
import 'package:dependencies_module/dependencies_module.dart';

import 'data/datasources/tenant_admin_grpc_datasource.dart';
import 'data/services/tenant_admin_service_impl.dart';
import 'domain/services/tenant_admin_service.dart';
import 'domain/usecases/accept_invite_usecase.dart';
import 'domain/usecases/create_invite_usecase.dart';
import 'domain/usecases/get_my_tenant_config_usecase.dart';
import 'domain/usecases/list_invites_usecase.dart';
import 'domain/usecases/list_tenant_users_usecase.dart';
import 'domain/usecases/revoke_invite_usecase.dart';
import 'domain/usecases/update_my_tenant_config_usecase.dart';
import 'domain/usecases/update_tenant_user_usecase.dart';
import 'presentation/config/routes/tenant_own_config_route.dart';
import 'presentation/convites/routes/accept_invite_route.dart';
import 'presentation/convites/routes/invites_route.dart';
import 'presentation/usuarios/routes/tenant_users_route.dart';

/// Módulo do painel do tenant (N3): convites, gestão de usuários/
/// `flow_permissions` e configuração do próprio tenant. Reusa o
/// `AdminServiceClient` gRPC-Web já exposto pelo `GrpcApiClient` global (mesma
/// borda usada por `admin_module`/`operacional_module`) — os RPCs aqui são
/// tenant-scoped (guard `exigir_autenticado_do_metadata`, não superuser).
final class TenantModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    i.lazySingleton<TenantAdminDataSource>(() {
      final client = inject<ApiClient>();
      if (client is GrpcApiClient) {
        return TenantAdminGrpcDatasourceImpl(client: client.admin);
      }
      throw StateError('ApiClient não é do tipo GrpcApiClient esperado.');
    });

    i.lazySingleton<TenantAdminService>(
      () => TenantAdminServiceImpl(datasource: inject<TenantAdminDataSource>()),
    );

    i.lazySingleton<CreateInviteUsecase>(
      () => CreateInviteUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<ListInvitesUsecase>(
      () => ListInvitesUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<RevokeInviteUsecase>(
      () => RevokeInviteUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<AcceptInviteUsecase>(
      () => AcceptInviteUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<ListTenantUsersUsecase>(
      () => ListTenantUsersUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<UpdateTenantUserUsecase>(
      () => UpdateTenantUserUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<GetMyTenantConfigUsecase>(
      () => GetMyTenantConfigUsecase(service: inject<TenantAdminService>()),
    );
    i.lazySingleton<UpdateMyTenantConfigUsecase>(
      () => UpdateMyTenantConfigUsecase(service: inject<TenantAdminService>()),
    );
  }

  @override
  List<GetItModule> routes() => [
        AcceptInviteRoute(),
        InvitesRoute(),
        TenantUsersRoute(),
        TenantOwnConfigRoute(),
      ];
}
