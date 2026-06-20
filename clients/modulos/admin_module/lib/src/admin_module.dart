import 'package:api_client/grpc_web_client.dart';
import 'package:dependencies_module/dependencies_module.dart';

import 'features/config/data/datasources/admin_grpc_datasource.dart';
import 'features/config/data/services/admin_service_impl.dart';
import 'features/config/domain/services/admin_service.dart';
import 'features/config/domain/usecases/list_core_settings_usecase.dart';
import 'features/config/domain/usecases/upsert_core_setting_usecase.dart';
import 'features/config/domain/usecases/delete_core_setting_usecase.dart';
import 'features/config/domain/usecases/get_tenant_config_usecase.dart';
import 'features/config/domain/usecases/update_tenant_config_usecase.dart';
import 'features/config/domain/usecases/list_tenants_usecase.dart';
import 'features/config/domain/usecases/get_tenant_usecase.dart';
import 'features/config/domain/usecases/create_tenant_usecase.dart';
import 'features/config/domain/usecases/update_tenant_usecase.dart';
import 'features/config/domain/usecases/set_tenant_active_usecase.dart';
import 'features/config/domain/usecases/generate_access_code_usecase.dart';
import 'features/config/domain/usecases/list_plans_usecase.dart';
import 'features/config/domain/usecases/create_plan_usecase.dart';
import 'features/config/domain/usecases/update_plan_usecase.dart';
import 'features/config/domain/usecases/list_subscriptions_usecase.dart';
import 'features/config/domain/usecases/register_payment_usecase.dart';
import 'features/config/domain/usecases/list_payments_usecase.dart';
import 'features/config/domain/usecases/test_evolution_connection_usecase.dart';
import 'features/config/domain/usecases/list_feature_flags_usecase.dart';
import 'features/config/domain/usecases/set_feature_flag_usecase.dart';
import 'features/config/domain/usecases/set_feature_flag_override_usecase.dart';
import 'features/config/domain/usecases/query_audit_log_usecase.dart';
import 'features/config/domain/usecases/get_service_health_usecase.dart';
import 'features/config/domain/usecases/get_dashboard_summary_usecase.dart';
import 'features/config/domain/usecases/export_tenants_csv_usecase.dart';
import 'features/config/presentation/routes/core_settings_route.dart';
import 'features/config/presentation/routes/tenant_config_route.dart';
import 'features/config/presentation/routes/tenants_route.dart';
import 'features/config/presentation/routes/billing_route.dart';
import 'features/config/presentation/routes/evolution_route.dart';
import 'features/config/presentation/routes/feature_flags_route.dart';
import 'features/config/presentation/routes/audit_route.dart';
import 'features/config/presentation/routes/dashboard_route.dart';

/// Módulo de Administração: registra dependências e rotas para gerenciamento.
final class AdminModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // Registra o client gRPC-Web recuperando-o do ApiClient global
    i.lazySingleton<AdminServiceClient>(() {
      final client = inject<ApiClient>();
      if (client is GrpcApiClient) {
        return client.admin;
      }
      throw StateError('ApiClient não é do tipo GrpcApiClient esperado.');
    });

    // Datasource
    i.lazySingleton<AdminGrpcDatasource>(
      () => AdminGrpcDatasourceImpl(client: inject<AdminServiceClient>()),
    );

    // Serviço/Repositório de domínio
    i.lazySingleton<AdminService>(
      () => AdminServiceImpl(datasource: inject<AdminGrpcDatasource>()),
    );

    // Usecases Fase 1
    i.lazySingleton<ListCoreSettingsUsecase>(
      () => ListCoreSettingsUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<UpsertCoreSettingUsecase>(
      () => UpsertCoreSettingUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<DeleteCoreSettingUsecase>(
      () => DeleteCoreSettingUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<GetTenantConfigUsecase>(
      () => GetTenantConfigUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<UpdateTenantConfigUsecase>(
      () => UpdateTenantConfigUsecase(service: inject<AdminService>()),
    );

    // Usecases Fase 2
    i.lazySingleton<ListTenantsUsecase>(
      () => ListTenantsUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<GetTenantUsecase>(
      () => GetTenantUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<CreateTenantUsecase>(
      () => CreateTenantUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<UpdateTenantUsecase>(
      () => UpdateTenantUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<SetTenantActiveUsecase>(
      () => SetTenantActiveUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<GenerateAccessCodeUsecase>(
      () => GenerateAccessCodeUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<ListPlansUsecase>(
      () => ListPlansUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<CreatePlanUsecase>(
      () => CreatePlanUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<UpdatePlanUsecase>(
      () => UpdatePlanUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<ListSubscriptionsUsecase>(
      () => ListSubscriptionsUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<RegisterPaymentUsecase>(
      () => RegisterPaymentUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<ListPaymentsUsecase>(
      () => ListPaymentsUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<TestEvolutionConnectionUsecase>(
      () => TestEvolutionConnectionUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<ListFeatureFlagsUsecase>(
      () => ListFeatureFlagsUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<SetFeatureFlagUsecase>(
      () => SetFeatureFlagUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<SetFeatureFlagOverrideUsecase>(
      () => SetFeatureFlagOverrideUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<QueryAuditLogUsecase>(
      () => QueryAuditLogUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<GetServiceHealthUsecase>(
      () => GetServiceHealthUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<GetDashboardSummaryUsecase>(
      () => GetDashboardSummaryUsecase(service: inject<AdminService>()),
    );
    i.lazySingleton<ExportTenantsCsvUsecase>(
      () => ExportTenantsCsvUsecase(service: inject<AdminService>()),
    );
  }

  @override
  List<GetItModule> routes() => [
        CoreSettingsRoute(),
        TenantConfigRoute(),
        TenantsRoute(),
        BillingRoute(),
        EvolutionRoute(),
        FeatureFlagsRoute(),
        AuditRoute(),
        DashboardRoute(),
      ];
}
