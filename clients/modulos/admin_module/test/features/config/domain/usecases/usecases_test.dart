import 'package:admin_module/src/features/config/domain/model/dashboard_summary.dart';
import 'package:admin_module/src/features/config/domain/model/evolution_connection_result.dart';
import 'package:admin_module/src/features/config/domain/model/plan.dart';
import 'package:admin_module/src/features/config/domain/model/tenant.dart';
import 'package:admin_module/src/features/config/domain/model/tenant_config.dart';
import 'package:admin_module/src/features/config/domain/services/admin_service.dart';
import 'package:admin_module/src/features/config/domain/usecases/create_plan_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/create_tenant_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/delete_core_setting_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/export_tenants_csv_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/generate_access_code_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/get_dashboard_summary_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/get_service_health_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/get_tenant_config_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/get_tenant_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_core_settings_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_feature_flags_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_payments_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_plans_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_subscriptions_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/list_tenants_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/query_audit_log_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/register_payment_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/set_feature_flag_override_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/set_feature_flag_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/set_tenant_active_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/test_evolution_connection_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/update_plan_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/update_tenant_config_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/update_tenant_usecase.dart';
import 'package:admin_module/src/features/config/domain/usecases/upsert_core_setting_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// Os usecases sao adaptadores finos: apenas delegam ao AdminService, encaminhando
// os argumentos. Aqui o AdminService e mockado para provar que cada usecase (1)
// repassa o resultado do service sem transformacao e (2) chama o metodo correto
// com os argumentos recebidos.
class _MockAdminService extends Mock implements AdminService {}

void main() {
  late _MockAdminService service;

  setUpAll(() {
    registerFallbackValue(tenantConfigFixture());
  });

  setUp(() {
    service = _MockAdminService();
  });

  group('ListCoreSettingsUsecase', () {
    test('delega para listCoreSettings', () async {
      final expected = SuccessReturn(success: [coreSettingFixture()]);
      when(() => service.listCoreSettings()).thenAnswer((_) async => expected);
      final res = await ListCoreSettingsUsecase(service: service).call();
      expect(res, same(expected));
      verify(() => service.listCoreSettings()).called(1);
    });
  });

  group('UpsertCoreSettingUsecase', () {
    test('encaminha os argumentos para upsertCoreSetting', () async {
      when(() => service.upsertCoreSetting(
            key: any(named: 'key'),
            value: any(named: 'value'),
            encrypted: any(named: 'encrypted'),
            description: any(named: 'description'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await UpsertCoreSettingUsecase(service: service).call(
          key: 'k', value: 'v', encrypted: true, description: 'd');
      verify(() => service.upsertCoreSetting(
          key: 'k', value: 'v', encrypted: true, description: 'd')).called(1);
    });
  });

  group('DeleteCoreSettingUsecase', () {
    test('encaminha a chave para deleteCoreSetting', () async {
      when(() => service.deleteCoreSetting(any()))
          .thenAnswer((_) async => const SuccessReturn(success: unit));
      await DeleteCoreSettingUsecase(service: service).call('k');
      verify(() => service.deleteCoreSetting('k')).called(1);
    });
  });

  group('GetTenantConfigUsecase', () {
    test('encaminha o tenantId para getTenantConfig', () async {
      when(() => service.getTenantConfig(any()))
          .thenAnswer((_) async => SuccessReturn(success: tenantConfigFixture()));
      final res = await GetTenantConfigUsecase(service: service).call('t');
      expect(res, isA<SuccessReturn<TenantConfig>>());
      verify(() => service.getTenantConfig('t')).called(1);
    });
  });

  group('UpdateTenantConfigUsecase', () {
    test('encaminha tenantId e config para updateTenantConfig', () async {
      final config = tenantConfigFixture();
      when(() => service.updateTenantConfig(
            tenantId: any(named: 'tenantId'),
            config: any(named: 'config'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await UpdateTenantConfigUsecase(service: service)
          .call(tenantId: 't', config: config);
      verify(() => service.updateTenantConfig(tenantId: 't', config: config))
          .called(1);
    });
  });

  group('ListTenantsUsecase', () {
    test('delega para listTenants', () async {
      final expected = SuccessReturn(success: [tenantFixture()]);
      when(() => service.listTenants()).thenAnswer((_) async => expected);
      final res = await ListTenantsUsecase(service: service).call();
      expect(res, same(expected));
      verify(() => service.listTenants()).called(1);
    });
  });

  group('GetTenantUsecase', () {
    test('encaminha o id para getTenant', () async {
      when(() => service.getTenant(any()))
          .thenAnswer((_) async => SuccessReturn(success: tenantFixture()));
      final res = await GetTenantUsecase(service: service).call('t');
      expect(res, isA<SuccessReturn<Tenant>>());
      verify(() => service.getTenant('t')).called(1);
    });
  });

  group('CreateTenantUsecase', () {
    test('encaminha os argumentos para createTenant', () async {
      when(() => service.createTenant(
            name: any(named: 'name'),
            slug: any(named: 'slug'),
            ownerId: any(named: 'ownerId'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => SuccessReturn(success: tenantFixture()));
      await CreateTenantUsecase(service: service).call(
          name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');
      verify(() => service.createTenant(
          name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p')).called(1);
    });
  });

  group('UpdateTenantUsecase', () {
    test('encaminha os argumentos para updateTenant', () async {
      when(() => service.updateTenant(
            id: any(named: 'id'),
            name: any(named: 'name'),
            slug: any(named: 'slug'),
            ownerId: any(named: 'ownerId'),
            email: any(named: 'email'),
            phone: any(named: 'phone'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await UpdateTenantUsecase(service: service).call(
          id: 'i', name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');
      verify(() => service.updateTenant(
          id: 'i',
          name: 'n',
          slug: 's',
          ownerId: 1,
          email: 'e',
          phone: 'p')).called(1);
    });
  });

  group('SetTenantActiveUsecase', () {
    test('encaminha id e active para setTenantActive', () async {
      when(() => service.setTenantActive(
            id: any(named: 'id'),
            active: any(named: 'active'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await SetTenantActiveUsecase(service: service)
          .call(id: 'i', active: false);
      verify(() => service.setTenantActive(id: 'i', active: false)).called(1);
    });
  });

  group('GenerateAccessCodeUsecase', () {
    test('encaminha o id para generateAccessCode', () async {
      when(() => service.generateAccessCode(any()))
          .thenAnswer((_) async => const SuccessReturn(success: 'CODE'));
      final res = await GenerateAccessCodeUsecase(service: service).call('i');
      expect((res as SuccessReturn).result, 'CODE');
      verify(() => service.generateAccessCode('i')).called(1);
    });
  });

  group('ListPlansUsecase', () {
    test('delega para listPlans', () async {
      when(() => service.listPlans())
          .thenAnswer((_) async => SuccessReturn(success: [planFixture()]));
      final res = await ListPlansUsecase(service: service).call();
      expect(res, isA<SuccessReturn<List<Plan>>>());
      verify(() => service.listPlans()).called(1);
    });
  });

  group('CreatePlanUsecase', () {
    test('encaminha os argumentos para createPlan', () async {
      when(() => service.createPlan(
            name: any(named: 'name'),
            description: any(named: 'description'),
            price: any(named: 'price'),
            maxInstances: any(named: 'maxInstances'),
            maxDepartments: any(named: 'maxDepartments'),
          )).thenAnswer((_) async => SuccessReturn(success: planFixture()));
      await CreatePlanUsecase(service: service).call(
          name: 'n',
          description: 'd',
          price: '1',
          maxInstances: 2,
          maxDepartments: 3);
      verify(() => service.createPlan(
          name: 'n',
          description: 'd',
          price: '1',
          maxInstances: 2,
          maxDepartments: 3)).called(1);
    });
  });

  group('UpdatePlanUsecase', () {
    test('encaminha os argumentos para updatePlan', () async {
      when(() => service.updatePlan(
            id: any(named: 'id'),
            name: any(named: 'name'),
            description: any(named: 'description'),
            price: any(named: 'price'),
            maxInstances: any(named: 'maxInstances'),
            maxDepartments: any(named: 'maxDepartments'),
            active: any(named: 'active'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await UpdatePlanUsecase(service: service).call(
          id: 1,
          name: 'n',
          description: 'd',
          price: '1',
          maxInstances: 2,
          maxDepartments: 3,
          active: true);
      verify(() => service.updatePlan(
          id: 1,
          name: 'n',
          description: 'd',
          price: '1',
          maxInstances: 2,
          maxDepartments: 3,
          active: true)).called(1);
    });
  });

  group('ListSubscriptionsUsecase', () {
    test('delega para listSubscriptions', () async {
      when(() => service.listSubscriptions())
          .thenAnswer((_) async => SuccessReturn(success: [subscriptionFixture()]));
      await ListSubscriptionsUsecase(service: service).call();
      verify(() => service.listSubscriptions()).called(1);
    });
  });

  group('RegisterPaymentUsecase', () {
    test('encaminha os argumentos para registerPayment', () async {
      when(() => service.registerPayment(
            tenantId: any(named: 'tenantId'),
            amount: any(named: 'amount'),
            paymentMethod: any(named: 'paymentMethod'),
            paymentDate: any(named: 'paymentDate'),
            periodStart: any(named: 'periodStart'),
            periodEnd: any(named: 'periodEnd'),
            notes: any(named: 'notes'),
          )).thenAnswer((_) async => SuccessReturn(success: paymentRecordFixture()));
      await RegisterPaymentUsecase(service: service).call(
          tenantId: 't',
          amount: '1',
          paymentMethod: 'pix',
          paymentDate: 'd',
          periodStart: 's',
          periodEnd: 'e',
          notes: 'n');
      verify(() => service.registerPayment(
          tenantId: 't',
          amount: '1',
          paymentMethod: 'pix',
          paymentDate: 'd',
          periodStart: 's',
          periodEnd: 'e',
          notes: 'n')).called(1);
    });
  });

  group('ListPaymentsUsecase', () {
    test('encaminha o tenantId opcional para listPayments', () async {
      when(() => service.listPayments(tenantId: any(named: 'tenantId')))
          .thenAnswer((_) async => SuccessReturn(success: [paymentRecordFixture()]));
      await ListPaymentsUsecase(service: service).call(tenantId: 't');
      verify(() => service.listPayments(tenantId: 't')).called(1);
    });
  });

  group('TestEvolutionConnectionUsecase', () {
    test('encaminha o tenantId para testEvolutionConnection', () async {
      when(() => service.testEvolutionConnection(any()))
          .thenAnswer((_) async => SuccessReturn(success: evolutionResultFixture()));
      final res = await TestEvolutionConnectionUsecase(service: service).call('t');
      expect(res, isA<SuccessReturn<EvolutionConnectionResult>>());
      verify(() => service.testEvolutionConnection('t')).called(1);
    });
  });

  group('ListFeatureFlagsUsecase', () {
    test('delega para listFeatureFlags', () async {
      when(() => service.listFeatureFlags())
          .thenAnswer((_) async => SuccessReturn(success: [featureFlagFixture()]));
      await ListFeatureFlagsUsecase(service: service).call();
      verify(() => service.listFeatureFlags()).called(1);
    });
  });

  group('SetFeatureFlagUsecase', () {
    test('encaminha key e enabledGlobally para setFeatureFlag', () async {
      when(() => service.setFeatureFlag(
            key: any(named: 'key'),
            enabledGlobally: any(named: 'enabledGlobally'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await SetFeatureFlagUsecase(service: service)
          .call(key: 'k', enabledGlobally: true);
      verify(() => service.setFeatureFlag(key: 'k', enabledGlobally: true))
          .called(1);
    });
  });

  group('SetFeatureFlagOverrideUsecase', () {
    test('encaminha os argumentos para setFeatureFlagOverride', () async {
      when(() => service.setFeatureFlagOverride(
            key: any(named: 'key'),
            tenantId: any(named: 'tenantId'),
            enabled: any(named: 'enabled'),
            removeOverride: any(named: 'removeOverride'),
          )).thenAnswer((_) async => const SuccessReturn(success: unit));
      await SetFeatureFlagOverrideUsecase(service: service).call(
          key: 'k', tenantId: 't', enabled: true, removeOverride: false);
      verify(() => service.setFeatureFlagOverride(
          key: 'k',
          tenantId: 't',
          enabled: true,
          removeOverride: false)).called(1);
    });
  });

  group('QueryAuditLogUsecase', () {
    test('encaminha os filtros para queryAuditLog', () async {
      when(() => service.queryAuditLog(
            tenantId: any(named: 'tenantId'),
            eventType: any(named: 'eventType'),
            limit: any(named: 'limit'),
            offset: any(named: 'offset'),
          )).thenAnswer((_) async => SuccessReturn(success: [auditLogEntryFixture()]));
      await QueryAuditLogUsecase(service: service).call(
          tenantId: 't', eventType: 'x', limit: 10, offset: 5);
      verify(() => service.queryAuditLog(
          tenantId: 't', eventType: 'x', limit: 10, offset: 5)).called(1);
    });
  });

  group('GetServiceHealthUsecase', () {
    test('delega para getServiceHealth', () async {
      when(() => service.getServiceHealth())
          .thenAnswer((_) async => SuccessReturn(success: [serviceHealthFixture()]));
      await GetServiceHealthUsecase(service: service).call();
      verify(() => service.getServiceHealth()).called(1);
    });
  });

  group('GetDashboardSummaryUsecase', () {
    test('delega para getDashboardSummary', () async {
      when(() => service.getDashboardSummary())
          .thenAnswer((_) async => SuccessReturn(success: dashboardSummaryFixture()));
      final res = await GetDashboardSummaryUsecase(service: service).call();
      expect(res, isA<SuccessReturn<DashboardSummary>>());
      verify(() => service.getDashboardSummary()).called(1);
    });
  });

  group('ExportTenantsCsvUsecase', () {
    test('delega para exportTenantsCsv', () async {
      when(() => service.exportTenantsCsv())
          .thenAnswer((_) async => const SuccessReturn(success: [1, 2, 3]));
      final res = await ExportTenantsCsvUsecase(service: service).call();
      expect((res as SuccessReturn).result, [1, 2, 3]);
      verify(() => service.exportTenantsCsv()).called(1);
    });
  });
}
