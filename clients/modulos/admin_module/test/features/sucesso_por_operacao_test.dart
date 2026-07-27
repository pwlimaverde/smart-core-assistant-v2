import 'package:admin_module/src/features/audit/data/datasources/audit_datasources.dart';
import 'package:admin_module/src/features/audit/data/repositories/audit_repositories.dart';
import 'package:admin_module/src/features/audit/domain/parameters/audit_parameters.dart';
import 'package:admin_module/src/features/audit/domain/usecases/audit_usecases.dart';
import 'package:admin_module/src/features/billing/data/datasources/billing_datasources.dart';
import 'package:admin_module/src/features/billing/data/repositories/billing_repositories.dart';
import 'package:admin_module/src/features/billing/domain/parameters/billing_parameters.dart';
import 'package:admin_module/src/features/billing/domain/usecases/billing_usecases.dart';
import 'package:admin_module/src/features/core_settings/data/datasources/core_settings_datasources.dart';
import 'package:admin_module/src/features/core_settings/data/repositories/core_settings_repositories.dart';
import 'package:admin_module/src/features/core_settings/domain/parameters/core_settings_parameters.dart';
import 'package:admin_module/src/features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'package:admin_module/src/features/dashboard/data/datasources/dashboard_datasources.dart';
import 'package:admin_module/src/features/dashboard/data/repositories/dashboard_repositories.dart';
import 'package:admin_module/src/features/dashboard/domain/usecases/dashboard_usecases.dart';
import 'package:admin_module/src/features/evolution/data/datasources/evolution_datasources.dart';
import 'package:admin_module/src/features/evolution/data/repositories/evolution_repositories.dart';
import 'package:admin_module/src/features/evolution/domain/parameters/evolution_parameters.dart';
import 'package:admin_module/src/features/evolution/domain/usecases/evolution_usecases.dart';
import 'package:admin_module/src/features/feature_flags/data/datasources/feature_flags_datasources.dart';
import 'package:admin_module/src/features/feature_flags/data/repositories/feature_flags_repositories.dart';
import 'package:admin_module/src/features/feature_flags/domain/parameters/feature_flags_parameters.dart';
import 'package:admin_module/src/features/feature_flags/domain/usecases/feature_flags_usecases.dart';
import 'package:admin_module/src/features/tenant_config/data/datasources/tenant_config_datasources.dart';
import 'package:admin_module/src/features/tenant_config/data/repositories/tenant_config_repositories.dart';
import 'package:admin_module/src/features/tenant_config/domain/parameters/tenant_config_parameters.dart';
import 'package:admin_module/src/features/tenant_config/domain/usecases/tenant_config_usecases.dart';
import 'package:admin_module/src/features/tenants/data/datasources/tenants_datasources.dart';
import 'package:admin_module/src/features/tenants/data/repositories/tenants_repositories.dart';
import 'package:admin_module/src/features/tenants/domain/parameters/tenants_parameters.dart';
import 'package:admin_module/src/features/tenants/domain/usecases/tenants_usecases.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../support/admin_grpc_mock.dart';
import '../support/fixtures.dart';

/// Caminho de sucesso das operações de escrita e leitura pontual.
///
/// A matriz de erro exercita o curto-circuito — e curto-circuito **não chama o
/// `process`**. Sem estes testes, o `process` de metade das operações nunca
/// rodaria, e um erro no passthrough (ou numa regra futura) passaria batido.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  test('upsertCoreSetting conclui em Unit', () async {
    when(
      () => client.upsertCoreSetting(any()),
    ).thenAnswer((_) => respostaGrpc(proto.UpsertCoreSettingResponse()));

    final r =
        await UpsertCoreSettingUsecase(
          repository: UpsertCoreSettingRepository(
            datasource: UpsertCoreSettingDatasource(client: client),
          ),
        )(
          const UpsertCoreSettingParameters(
            key: 'k',
            value: 'v',
            encrypted: false,
            description: 'd',
          ),
        );

    expect(r, isA<Success>());
    expect((r as Success).value, unit);
  });

  test('deleteCoreSetting envia a chave e conclui em Unit', () async {
    when(
      () => client.deleteCoreSetting(any()),
    ).thenAnswer((_) => respostaGrpc(proto.DeleteCoreSettingResponse()));

    final r = await DeleteCoreSettingUsecase(
      repository: DeleteCoreSettingRepository(
        datasource: DeleteCoreSettingDatasource(client: client),
      ),
    )(const DeleteCoreSettingParameters(key: 'openai_api_key'));

    expect((r as Success).value, unit);
    final enviado =
        verify(() => client.deleteCoreSetting(captureAny())).captured.single
            as proto.DeleteCoreSettingRequest;
    expect(enviado.key, 'openai_api_key');
  });

  test('getTenant converte o tenant pedido', () async {
    when(() => client.getTenant(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetTenantResponse(
          tenant: proto.Tenant(
            id: 't5',
            name: 'Empresa Gama',
            slug: 'gama',
            apiKey: 'k',
            ownerId: 2,
            email: 'g@x.com',
            phone: '1',
            active: false,
            createdAt: ms(DateTime(2026, 1, 1)),
            updatedAt: ms(DateTime(2026, 1, 2)),
          ),
        ),
      ),
    );

    final r = await GetTenantUsecase(
      repository: GetTenantRepository(
        datasource: GetTenantDatasource(client: client),
      ),
    )(const GetTenantParameters(id: 't5'));

    final t = (r as Success).value;
    expect(t.id, 't5');
    expect(t.name, 'Empresa Gama');
    expect(t.active, isFalse);
  });

  test('updateTenant envia todos os campos editáveis', () async {
    when(
      () => client.updateTenant(any()),
    ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantResponse()));

    final r =
        await UpdateTenantUsecase(
          repository: UpdateTenantRepository(
            datasource: UpdateTenantDatasource(client: client),
          ),
        )(
          const UpdateTenantParameters(
            id: 't1',
            name: 'Novo Nome',
            slug: 'novo-slug',
            ownerId: 3,
            email: 'novo@x.com',
            phone: '11777',
          ),
        );

    expect(r, isA<Success>());
    final enviado =
        verify(() => client.updateTenant(captureAny())).captured.single
            as proto.UpdateTenantRequest;
    expect(enviado.id, 't1');
    expect(enviado.name, 'Novo Nome');
    expect(enviado.slug, 'novo-slug');
    expect(enviado.ownerId, 3);
    expect(enviado.email, 'novo@x.com');
    expect(enviado.phone, '11777');
  });

  test('updateTenantConfig conclui em Unit', () async {
    when(
      () => client.updateTenantConfig(any()),
    ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantConfigResponse()));

    final r =
        await UpdateTenantConfigUsecase(
          repository: UpdateTenantConfigRepository(
            datasource: UpdateTenantConfigDatasource(client: client),
          ),
        )(
          UpdateTenantConfigParameters(
            tenantId: 't1',
            config: tenantConfigFixture(),
          ),
        );

    expect((r as Success).value, unit);
  });

  test('updatePlan envia os limites e o estado do plano', () async {
    when(
      () => client.updatePlan(any()),
    ).thenAnswer((_) => respostaGrpc(proto.UpdatePlanResponse(success: true)));

    final r =
        await UpdatePlanUsecase(
          repository: UpdatePlanRepository(
            datasource: UpdatePlanDatasource(client: client),
          ),
        )(
          const UpdatePlanParameters(
            id: 7,
            name: 'Pro',
            description: 'd',
            price: '299.00',
            maxInstances: 5,
            maxDepartments: 10,
            active: false,
          ),
        );

    expect(r, isA<Success>());
    final enviado =
        verify(() => client.updatePlan(captureAny())).captured.single
            as proto.UpdatePlanRequest;
    expect(enviado.id, 7);
    expect(enviado.active, isFalse);
    expect(enviado.maxDepartments, 10);
  });

  test('setFeatureFlag conclui em Unit', () async {
    when(() => client.setFeatureFlag(any())).thenAnswer(
      (_) => respostaGrpc(proto.SetFeatureFlagResponse(success: true)),
    );

    final r = await SetFeatureFlagUsecase(
      repository: SetFeatureFlagRepository(
        datasource: SetFeatureFlagDatasource(client: client),
      ),
    )(const SetFeatureFlagParameters(key: 'k', enabledGlobally: false));

    expect((r as Success).value, unit);
  });

  test('setFeatureFlagOverride conclui em Unit', () async {
    when(() => client.setFeatureFlagOverride(any())).thenAnswer(
      (_) => respostaGrpc(proto.SetFeatureFlagOverrideResponse(success: true)),
    );

    final r =
        await SetFeatureFlagOverrideUsecase(
          repository: SetFeatureFlagOverrideRepository(
            datasource: SetFeatureFlagOverrideDatasource(client: client),
          ),
        )(
          const SetFeatureFlagOverrideParameters(
            key: 'k',
            tenantId: 't1',
            enabled: true,
            removeOverride: false,
          ),
        );

    expect((r as Success).value, unit);
  });

  test('getServiceHealth converte a lista de serviços', () async {
    when(() => client.getServiceHealth(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.GetServiceHealthResponse(
          services: [
            proto.ServiceHealth(
              serviceName: 'worker',
              status: 'up',
              message: 'ok',
            ),
          ],
        ),
      ),
    );

    final r = await GetServiceHealthUsecase(
      repository: GetServiceHealthRepository(
        datasource: GetServiceHealthDatasource(client: client),
      ),
    )(noParams);

    expect((r as Success).value.single.serviceName, 'worker');
  });

  test('queryAuditLog sem filtros envia os campos vazios', () async {
    when(() => client.queryAuditLog(any())).thenAnswer(
      (_) => respostaGrpc(proto.QueryAuditLogResponse(totalCount: 0)),
    );

    final r = await QueryAuditLogUsecase(
      repository: QueryAuditLogRepository(
        datasource: QueryAuditLogDatasource(client: client),
      ),
    )(const QueryAuditLogParameters());

    expect((r as Success).value, isEmpty);
    final enviado =
        verify(() => client.queryAuditLog(captureAny())).captured.single
            as proto.QueryAuditLogRequest;
    expect(enviado.tenantId, isEmpty);
    expect(enviado.eventType, isEmpty);
  });

  test('testEvolutionConnection envia o tenant', () async {
    when(() => client.testEvolutionConnection(any())).thenAnswer(
      (_) =>
          respostaGrpc(proto.TestEvolutionConnectionResponse(status: 'open')),
    );

    final r = await TestEvolutionConnectionUsecase(
      repository: TestEvolutionConnectionRepository(
        datasource: TestEvolutionConnectionDatasource(client: client),
      ),
    )(const TestEvolutionConnectionParameters(tenantId: 't3'));

    expect((r as Success).value.status, 'open');
    final enviado =
        verify(
              () => client.testEvolutionConnection(captureAny()),
            ).captured.single
            as proto.TestEvolutionConnectionRequest;
    expect(enviado.tenantId, 't3');
  });
}
