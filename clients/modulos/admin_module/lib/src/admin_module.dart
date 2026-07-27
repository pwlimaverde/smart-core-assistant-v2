import 'package:dependencies_module/dependencies_module.dart';

import 'features/core_settings/data/datasources/core_settings_datasources.dart';
import 'features/core_settings/data/repositories/core_settings_repositories.dart';
import 'features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'features/core_settings/presentation/routes/core_settings_route.dart';
import 'features/tenants/data/datasources/tenants_datasources.dart';
import 'features/tenants/data/repositories/tenants_repositories.dart';
import 'features/tenants/domain/usecases/tenants_usecases.dart';
import 'features/tenants/presentation/routes/tenants_route.dart';
import 'features/tenant_config/data/datasources/tenant_config_datasources.dart';
import 'features/tenant_config/data/repositories/tenant_config_repositories.dart';
import 'features/tenant_config/domain/usecases/tenant_config_usecases.dart';
import 'features/tenant_config/presentation/routes/tenant_config_route.dart';
import 'features/billing/data/datasources/billing_datasources.dart';
import 'features/billing/data/repositories/billing_repositories.dart';
import 'features/billing/domain/usecases/billing_usecases.dart';
import 'features/billing/presentation/routes/billing_route.dart';
import 'features/feature_flags/data/datasources/feature_flags_datasources.dart';
import 'features/feature_flags/data/repositories/feature_flags_repositories.dart';
import 'features/feature_flags/domain/usecases/feature_flags_usecases.dart';
import 'features/feature_flags/presentation/routes/feature_flags_route.dart';
import 'features/audit/data/datasources/audit_datasources.dart';
import 'features/audit/data/repositories/audit_repositories.dart';
import 'features/audit/domain/usecases/audit_usecases.dart';
import 'features/audit/presentation/routes/audit_route.dart';
import 'features/evolution/data/datasources/evolution_datasources.dart';
import 'features/evolution/data/repositories/evolution_repositories.dart';
import 'features/evolution/domain/usecases/evolution_usecases.dart';
import 'features/evolution/presentation/routes/evolution_route.dart';
import 'features/dashboard/data/datasources/dashboard_datasources.dart';
import 'features/dashboard/data/repositories/dashboard_repositories.dart';
import 'features/dashboard/domain/usecases/dashboard_usecases.dart';
import 'features/dashboard/presentation/routes/dashboard_route.dart';

/// Módulo de administração (painel do superusuário), em **oito features**:
/// core_settings, tenants, tenant_config, billing, feature_flags, audit,
/// evolution e dashboard.
///
/// Antes existia uma única feature `config` com tudo dentro, servida por um
/// `AdminService` de 24 métodos, um `AdminServiceImpl` que repetia o mesmo
/// `try/catch` 24 vezes e um datasource gRPC de 746 linhas. Os três foram
/// deletados: cada operação agora tem a sua cadeia
/// `Datasource → Repository → Usecase`, montada aqui.
final class AdminModule extends AppModule {
  @override
  void globalBinds(Injector i) {
    // ── core_settings ─────────────────────────────────────────────────
    i.lazySingleton<ListCoreSettingsUsecase>(
      () => ListCoreSettingsUsecase(
        repository: ListCoreSettingsRepository(
          datasource: ListCoreSettingsDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<UpsertCoreSettingUsecase>(
      () => UpsertCoreSettingUsecase(
        repository: UpsertCoreSettingRepository(
          datasource: UpsertCoreSettingDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<DeleteCoreSettingUsecase>(
      () => DeleteCoreSettingUsecase(
        repository: DeleteCoreSettingRepository(
          datasource: DeleteCoreSettingDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── tenants ───────────────────────────────────────────────────────
    i.lazySingleton<ListTenantsUsecase>(
      () => ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<GetTenantUsecase>(
      () => GetTenantUsecase(
        repository: GetTenantRepository(
          datasource: GetTenantDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<CreateTenantUsecase>(
      () => CreateTenantUsecase(
        repository: CreateTenantRepository(
          datasource: CreateTenantDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<UpdateTenantUsecase>(
      () => UpdateTenantUsecase(
        repository: UpdateTenantRepository(
          datasource: UpdateTenantDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<SetTenantActiveUsecase>(
      () => SetTenantActiveUsecase(
        repository: SetTenantActiveRepository(
          datasource: SetTenantActiveDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<GenerateAccessCodeUsecase>(
      () => GenerateAccessCodeUsecase(
        repository: GenerateAccessCodeRepository(
          datasource: GenerateAccessCodeDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<ExportTenantsCsvUsecase>(
      () => ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── tenant_config ─────────────────────────────────────────────────
    i.lazySingleton<GetTenantConfigUsecase>(
      () => GetTenantConfigUsecase(
        repository: GetTenantConfigRepository(
          datasource: GetTenantConfigDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<UpdateTenantConfigUsecase>(
      () => UpdateTenantConfigUsecase(
        repository: UpdateTenantConfigRepository(
          datasource: UpdateTenantConfigDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── billing ───────────────────────────────────────────────────────
    i.lazySingleton<ListPlansUsecase>(
      () => ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<CreatePlanUsecase>(
      () => CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<UpdatePlanUsecase>(
      () => UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<ListSubscriptionsUsecase>(
      () => ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<RegisterPaymentUsecase>(
      () => RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<ListPaymentsUsecase>(
      () => ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── feature_flags ─────────────────────────────────────────────────
    i.lazySingleton<ListFeatureFlagsUsecase>(
      () => ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<SetFeatureFlagUsecase>(
      () => SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<SetFeatureFlagOverrideUsecase>(
      () => SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── audit ─────────────────────────────────────────────────────────
    i.lazySingleton<QueryAuditLogUsecase>(
      () => QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── evolution ─────────────────────────────────────────────────────
    i.lazySingleton<TestEvolutionConnectionUsecase>(
      () => TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: _adminClient()),
        ),
      ),
    );

    // ── dashboard ─────────────────────────────────────────────────────
    i.lazySingleton<GetServiceHealthUsecase>(
      () => GetServiceHealthUsecase(
        repository: GetServiceHealthRepository(
          datasource: GetServiceHealthDatasource(client: _adminClient()),
        ),
      ),
    );
    i.lazySingleton<GetDashboardSummaryUsecase>(
      () => GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: _adminClient()),
        ),
      ),
    );
  }

  @override
  List<GetItModule> routes() => [
    CoreSettingsRoute(),
    TenantsRoute(),
    TenantConfigRoute(),
    BillingRoute(),
    FeatureFlagsRoute(),
    AuditRoute(),
    EvolutionRoute(),
    DashboardRoute(),
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
