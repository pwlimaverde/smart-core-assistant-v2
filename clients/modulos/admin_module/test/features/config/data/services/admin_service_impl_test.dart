import 'package:admin_module/src/features/config/data/datasources/admin_grpc_datasource.dart';
import 'package:admin_module/src/features/config/data/services/admin_service_impl.dart';
import 'package:admin_module/src/features/config/domain/model/core_setting.dart';
import 'package:admin_module/src/features/config/domain/model/dashboard_summary.dart';
import 'package:admin_module/src/features/config/domain/model/evolution_connection_result.dart';
import 'package:admin_module/src/features/config/domain/model/payment_record.dart';
import 'package:admin_module/src/features/config/domain/model/plan.dart';
import 'package:admin_module/src/features/config/domain/model/tenant.dart';
import 'package:admin_module/src/features/config/domain/model/tenant_config.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../../../support/fixtures.dart';

// AdminServiceImpl encapsula o AdminGrpcDatasource (a fronteira externa, I/O gRPC)
// num try/catch, convertendo o resultado em ReturnSuccessOrError. Aqui a fronteira
// e mockada com mocktail para exercitar os tres ramos de cada metodo:
//  - sucesso -> SuccessReturn com o dado do datasource;
//  - AppError tipado -> propagado como ErrorReturn (mesmo tipo);
//  - excecao generica -> mapeada para ErrorNetwork com a mensagem original.
class _MockDatasource extends Mock implements AdminGrpcDatasource {}

void main() {
  late _MockDatasource datasource;
  late AdminServiceImpl service;

  setUpAll(() {
    registerFallbackValue(tenantConfigFixture());
  });

  setUp(() {
    datasource = _MockDatasource();
    service = AdminServiceImpl(datasource: datasource);
  });

  // Valida os dois ramos de erro comuns a todos os metodos do service.
  //
  // [whenCall] devolve o `When` do metodo mockado (para re-stubar com thenThrow);
  // [act] chama o metodo do service. Como cada metodo tem o mesmo formato de
  // try/catch, centralizamos aqui a verificacao dos ramos AppError e generico.
  Future<void> expectErrorBranches<T>(
    dynamic Function() whenCall,
    Future<ReturnSuccessOrError<T>> Function() act,
  ) async {
    // Ramo AppError: propagado como esta.
    whenCall().thenThrow(const ErrorUnauthorized(message: 'Acesso negado.'));
    final appErr = await act();
    expect(appErr, isA<ErrorReturn<T>>());
    expect((appErr as ErrorReturn).result, isA<ErrorUnauthorized>());

    // Ramo generico: vira ErrorNetwork com a mensagem original.
    whenCall().thenThrow(Exception('falha de transporte'));
    final genErr = await act();
    expect(genErr, isA<ErrorReturn<T>>());
    final error = (genErr as ErrorReturn).result;
    expect(error, isA<ErrorNetwork>());
    expect(error.message, contains('falha de transporte'));
  }

  group('listCoreSettings', () {
    dynamic whenCall() => when(() => datasource.listCoreSettings());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [coreSettingFixture()]);
      final res = await service.listCoreSettings();
      expect(res, isA<SuccessReturn<List<CoreSetting>>>());
      expect((res as SuccessReturn).result, hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, service.listCoreSettings));
  });

  group('upsertCoreSetting', () {
    dynamic whenCall() => when(() => datasource.upsertCoreSetting(
          key: any(named: 'key'),
          value: any(named: 'value'),
          encrypted: any(named: 'encrypted'),
          description: any(named: 'description'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() => service.upsertCoreSetting(
        key: 'k', value: 'v', encrypted: false, description: 'd');
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('deleteCoreSetting', () {
    dynamic whenCall() => when(() => datasource.deleteCoreSetting(any()));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await service.deleteCoreSetting('k'), isA<SuccessReturn<Unit>>());
    });
    test('erros',
        () => expectErrorBranches(whenCall, () => service.deleteCoreSetting('k')));
  });

  group('getTenantConfig', () {
    dynamic whenCall() => when(() => datasource.getTenantConfig(any()));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => tenantConfigFixture());
      expect(await service.getTenantConfig('t'),
          isA<SuccessReturn<TenantConfig>>());
    });
    test('erros',
        () => expectErrorBranches(whenCall, () => service.getTenantConfig('t')));
  });

  group('updateTenantConfig', () {
    dynamic whenCall() => when(() => datasource.updateTenantConfig(
          tenantId: any(named: 'tenantId'),
          config: any(named: 'config'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() => service.updateTenantConfig(
        tenantId: 't', config: tenantConfigFixture());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('listTenants', () {
    dynamic whenCall() => when(() => datasource.listTenants());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [tenantFixture()]);
      expect((await service.listTenants() as SuccessReturn).result, hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, service.listTenants));
  });

  group('getTenant', () {
    dynamic whenCall() => when(() => datasource.getTenant(any()));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => tenantFixture());
      expect(await service.getTenant('t'), isA<SuccessReturn<Tenant>>());
    });
    test('erros',
        () => expectErrorBranches(whenCall, () => service.getTenant('t')));
  });

  group('createTenant', () {
    dynamic whenCall() => when(() => datasource.createTenant(
          name: any(named: 'name'),
          slug: any(named: 'slug'),
          ownerId: any(named: 'ownerId'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
        ));
    Future<ReturnSuccessOrError<Tenant>> act() => service.createTenant(
        name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => tenantFixture());
      expect(await act(), isA<SuccessReturn<Tenant>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('updateTenant', () {
    dynamic whenCall() => when(() => datasource.updateTenant(
          id: any(named: 'id'),
          name: any(named: 'name'),
          slug: any(named: 'slug'),
          ownerId: any(named: 'ownerId'),
          email: any(named: 'email'),
          phone: any(named: 'phone'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() => service.updateTenant(
        id: 'i', name: 'n', slug: 's', ownerId: 1, email: 'e', phone: 'p');
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('setTenantActive', () {
    dynamic whenCall() => when(() => datasource.setTenantActive(
          id: any(named: 'id'),
          active: any(named: 'active'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() =>
        service.setTenantActive(id: 'i', active: false);
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('generateAccessCode', () {
    dynamic whenCall() => when(() => datasource.generateAccessCode(any()));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => 'CODE');
      expect((await service.generateAccessCode('i') as SuccessReturn).result,
          'CODE');
    });
    test('erros',
        () => expectErrorBranches(whenCall, () => service.generateAccessCode('i')));
  });

  group('listPlans', () {
    dynamic whenCall() => when(() => datasource.listPlans());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [planFixture()]);
      expect((await service.listPlans() as SuccessReturn).result, hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, service.listPlans));
  });

  group('createPlan', () {
    dynamic whenCall() => when(() => datasource.createPlan(
          name: any(named: 'name'),
          description: any(named: 'description'),
          price: any(named: 'price'),
          maxInstances: any(named: 'maxInstances'),
          maxDepartments: any(named: 'maxDepartments'),
        ));
    Future<ReturnSuccessOrError<Plan>> act() => service.createPlan(
        name: 'n',
        description: 'd',
        price: '1',
        maxInstances: 1,
        maxDepartments: 1);
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => planFixture());
      expect(await act(), isA<SuccessReturn<Plan>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('updatePlan', () {
    dynamic whenCall() => when(() => datasource.updatePlan(
          id: any(named: 'id'),
          name: any(named: 'name'),
          description: any(named: 'description'),
          price: any(named: 'price'),
          maxInstances: any(named: 'maxInstances'),
          maxDepartments: any(named: 'maxDepartments'),
          active: any(named: 'active'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() => service.updatePlan(
        id: 1,
        name: 'n',
        description: 'd',
        price: '1',
        maxInstances: 1,
        maxDepartments: 1,
        active: true);
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('listSubscriptions', () {
    dynamic whenCall() => when(() => datasource.listSubscriptions());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [subscriptionFixture()]);
      expect((await service.listSubscriptions() as SuccessReturn).result,
          hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, service.listSubscriptions));
  });

  group('registerPayment', () {
    dynamic whenCall() => when(() => datasource.registerPayment(
          tenantId: any(named: 'tenantId'),
          amount: any(named: 'amount'),
          paymentMethod: any(named: 'paymentMethod'),
          paymentDate: any(named: 'paymentDate'),
          periodStart: any(named: 'periodStart'),
          periodEnd: any(named: 'periodEnd'),
          notes: any(named: 'notes'),
        ));
    Future<ReturnSuccessOrError<PaymentRecord>> act() => service.registerPayment(
        tenantId: 't',
        amount: '1',
        paymentMethod: 'pix',
        paymentDate: 'd',
        periodStart: 's',
        periodEnd: 'e',
        notes: 'n');
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => paymentRecordFixture());
      expect(await act(), isA<SuccessReturn<PaymentRecord>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('listPayments', () {
    dynamic whenCall() =>
        when(() => datasource.listPayments(tenantId: any(named: 'tenantId')));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [paymentRecordFixture()]);
      expect((await service.listPayments(tenantId: 't') as SuccessReturn).result,
          hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, () => service.listPayments()));
  });

  group('testEvolutionConnection', () {
    dynamic whenCall() => when(() => datasource.testEvolutionConnection(any()));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => evolutionResultFixture());
      expect(await service.testEvolutionConnection('t'),
          isA<SuccessReturn<EvolutionConnectionResult>>());
    });
    test(
        'erros',
        () => expectErrorBranches(
            whenCall, () => service.testEvolutionConnection('t')));
  });

  group('listFeatureFlags', () {
    dynamic whenCall() => when(() => datasource.listFeatureFlags());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [featureFlagFixture()]);
      expect((await service.listFeatureFlags() as SuccessReturn).result,
          hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, service.listFeatureFlags));
  });

  group('setFeatureFlag', () {
    dynamic whenCall() => when(() => datasource.setFeatureFlag(
          key: any(named: 'key'),
          enabledGlobally: any(named: 'enabledGlobally'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() =>
        service.setFeatureFlag(key: 'k', enabledGlobally: true);
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('setFeatureFlagOverride', () {
    dynamic whenCall() => when(() => datasource.setFeatureFlagOverride(
          key: any(named: 'key'),
          tenantId: any(named: 'tenantId'),
          enabled: any(named: 'enabled'),
          removeOverride: any(named: 'removeOverride'),
        ));
    Future<ReturnSuccessOrError<Unit>> act() => service.setFeatureFlagOverride(
        key: 'k', tenantId: 't', enabled: true, removeOverride: false);
    test('sucesso', () async {
      whenCall().thenAnswer((_) async {});
      expect(await act(), isA<SuccessReturn<Unit>>());
    });
    test('erros', () => expectErrorBranches(whenCall, act));
  });

  group('queryAuditLog', () {
    dynamic whenCall() => when(() => datasource.queryAuditLog(
          tenantId: any(named: 'tenantId'),
          eventType: any(named: 'eventType'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ));
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [auditLogEntryFixture()]);
      expect((await service.queryAuditLog() as SuccessReturn).result,
          hasLength(1));
    });
    test(
        'erros',
        () => expectErrorBranches(
            whenCall, () => service.queryAuditLog(tenantId: 't', eventType: 'x')));
  });

  group('getServiceHealth', () {
    dynamic whenCall() => when(() => datasource.getServiceHealth());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [serviceHealthFixture()]);
      expect((await service.getServiceHealth() as SuccessReturn).result,
          hasLength(1));
    });
    test('erros', () => expectErrorBranches(whenCall, service.getServiceHealth));
  });

  group('getDashboardSummary', () {
    dynamic whenCall() => when(() => datasource.getDashboardSummary());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => dashboardSummaryFixture());
      expect(await service.getDashboardSummary(),
          isA<SuccessReturn<DashboardSummary>>());
    });
    test(
        'erros', () => expectErrorBranches(whenCall, service.getDashboardSummary));
  });

  group('exportTenantsCsv', () {
    dynamic whenCall() => when(() => datasource.exportTenantsCsv());
    test('sucesso', () async {
      whenCall().thenAnswer((_) async => [1, 2, 3]);
      expect((await service.exportTenantsCsv() as SuccessReturn).result,
          [1, 2, 3]);
    });
    test('erros', () => expectErrorBranches(whenCall, service.exportTenantsCsv));
  });
}
