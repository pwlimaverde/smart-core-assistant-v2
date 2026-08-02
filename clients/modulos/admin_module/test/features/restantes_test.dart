import 'package:admin_module/src/features/audit/data/datasources/audit_datasources.dart';
import 'package:admin_module/src/features/audit/data/repositories/audit_repositories.dart';
import 'package:admin_module/src/features/audit/domain/model/audit_log_entry.dart';
import 'package:admin_module/src/features/audit/domain/parameters/audit_parameters.dart';
import 'package:admin_module/src/features/audit/domain/usecases/audit_usecases.dart';
import 'package:admin_module/src/features/audit/presentation/controllers/audit_controller.dart';
import 'package:admin_module/src/features/billing/data/datasources/billing_datasources.dart';
import 'package:admin_module/src/features/billing/data/repositories/billing_repositories.dart';
import 'package:admin_module/src/features/billing/domain/errors/billing_errors.dart';
import 'package:admin_module/src/features/billing/domain/parameters/billing_parameters.dart';
import 'package:admin_module/src/features/billing/domain/usecases/billing_usecases.dart';
import 'package:admin_module/src/features/billing/presentation/controllers/billing_controller.dart';
import 'package:admin_module/src/features/dashboard/data/datasources/dashboard_datasources.dart';
import 'package:admin_module/src/features/dashboard/data/repositories/dashboard_repositories.dart';
import 'package:admin_module/src/features/dashboard/domain/model/dashboard_summary.dart';
import 'package:admin_module/src/features/dashboard/domain/usecases/dashboard_usecases.dart';
import 'package:admin_module/src/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:admin_module/src/features/evolution/data/datasources/evolution_datasources.dart';
import 'package:admin_module/src/features/evolution/data/repositories/evolution_repositories.dart';
import 'package:admin_module/src/features/evolution/domain/usecases/evolution_usecases.dart';
import 'package:admin_module/src/features/evolution/presentation/controllers/evolution_controller.dart';
import 'package:admin_module/src/features/feature_flags/data/datasources/feature_flags_datasources.dart';
import 'package:admin_module/src/features/feature_flags/data/repositories/feature_flags_repositories.dart';
import 'package:admin_module/src/features/feature_flags/domain/model/feature_flag.dart';
import 'package:admin_module/src/features/feature_flags/domain/parameters/feature_flags_parameters.dart';
import 'package:admin_module/src/features/feature_flags/domain/usecases/feature_flags_usecases.dart';
import 'package:admin_module/src/features/feature_flags/presentation/controllers/feature_flags_controller.dart';
import 'package:admin_module/src/features/tenant_config/data/datasources/tenant_config_datasources.dart';
import 'package:admin_module/src/features/tenant_config/data/repositories/tenant_config_repositories.dart';
import 'package:admin_module/src/features/tenant_config/domain/model/tenant_config.dart';
import 'package:admin_module/src/features/tenant_config/domain/parameters/tenant_config_parameters.dart';
import 'package:admin_module/src/features/tenant_config/domain/usecases/tenant_config_usecases.dart';
import 'package:admin_module/src/features/tenant_config/presentation/controllers/tenant_config_controller.dart';
import 'package:admin_module/src/features/tenants/data/datasources/tenants_datasources.dart';
import 'package:admin_module/src/features/tenants/data/repositories/tenants_repositories.dart';
import 'package:admin_module/src/features/tenants/domain/model/tenant.dart';
import 'package:admin_module/src/features/tenants/domain/usecases/tenants_usecases.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:fixnum/fixnum.dart';
import 'package:api_client/testing.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../support/admin_grpc_mock.dart';
import '../support/fixtures.dart';

/// Caminho de sucesso das seis features restantes: conversão protobuf → domínio
/// e orquestração dos controllers.
///
/// A matriz de erro por feature (`*_errors_matrix_test.dart`) cobre o outro lado.
void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  // ── tenant_config ────────────────────────────────────────────────────────
  group('tenant_config', () {
    GetTenantConfigUsecase get() => GetTenantConfigUsecase(
      repository: GetTenantConfigRepository(
        datasource: GetTenantConfigDatasource(client: client),
      ),
    );
    UpdateTenantConfigUsecase update() => UpdateTenantConfigUsecase(
      repository: UpdateTenantConfigRepository(
        datasource: UpdateTenantConfigDatasource(client: client),
      ),
    );

    void leituraResponde() =>
        when(() => client.getTenantConfig(any())).thenAnswer(
          (_) => respostaGrpc(
            proto.GetTenantConfigResponse(
              dadosEmpresa: 'Empresa X',
              personaBot: 'cordial',
              botAgentName: 'Aria',
              llmClass: 'openai',
              model: 'gpt-4o',
              llmTemperature: '0.7',
              chunkSize: 512,
              chunkOverlap: 64,
              similarityThreshold: '0.8',
              vectorDistanceThreshold: '0.4',
              apiKeys: [proto.ApiKeyEntry(key: 'openai', value: '****')],
            ),
          ),
        );

    test('leitura converte os campos e o mapa de chaves', () async {
      leituraResponde();

      final r = await get()(const GetTenantConfigParameters(tenantId: 't1'));

      final c = (r as Success<TenantConfig, dynamic>).value;
      expect(c.botAgentName, 'Aria');
      expect(c.chunkSize, 512);
      expect(c.apiKeys, {'openai': '****'});
    });

    test('leitura envia o tenant pedido', () async {
      leituraResponde();

      await get()(const GetTenantConfigParameters(tenantId: 't42'));

      final enviado =
          verify(() => client.getTenantConfig(captureAny())).captured.single
              as proto.GetTenantConfigRequest;
      expect(enviado.tenantId, 't42');
    });

    test('gravação envia o tenant e a configuração inteira', () async {
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantConfigResponse()));

      await update()(
        UpdateTenantConfigParameters(
          tenantId: 't1',
          config: tenantConfigFixture(),
        ),
      );

      final enviado =
          verify(() => client.updateTenantConfig(captureAny())).captured.single
              as proto.UpdateTenantConfigRequest;
      expect(enviado.tenantId, 't1');
      expect(enviado.botAgentName, 'Aria');
      expect(enviado.apiKeys, isNotEmpty);
    });

    blocTest<TenantConfigController, ViewState<TenantConfig>>(
      'controller carrega a configuração do tenant',
      build: () {
        leituraResponde();
        return TenantConfigController(
          getUsecase: get(),
          updateUsecase: update(),
        );
      },
      act: (c) => c.fetchConfig('t1'),
      expect: () => [
        isA<LoadingState<TenantConfig>>(),
        isA<SuccessState<TenantConfig>>().having(
          (s) => s.data.botAgentName,
          'botAgentName',
          'Aria',
        ),
      ],
    );

    test('controller recarrega após salvar com sucesso', () async {
      leituraResponde();
      when(
        () => client.updateTenantConfig(any()),
      ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantConfigResponse()));
      final controller = TenantConfigController(
        getUsecase: get(),
        updateUsecase: update(),
      );

      final r = await controller.updateConfig(
        tenantId: 't1',
        config: tenantConfigFixture(),
      );

      expect(r, isA<Success>());
      verify(() => client.getTenantConfig(any())).called(1);
      await controller.close();
    });
  });

  // ── billing ──────────────────────────────────────────────────────────────
  group('billing', () {
    BillingController controller() => BillingController(
      listPlansUsecase: ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      ),
      createPlanUsecase: CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      ),
      updatePlanUsecase: UpdatePlanUsecase(
        repository: UpdatePlanRepository(
          datasource: UpdatePlanDatasource(client: client),
        ),
      ),
      listSubscriptionsUsecase: ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      ),
      registerPaymentUsecase: RegisterPaymentUsecase(
        repository: RegisterPaymentRepository(
          datasource: RegisterPaymentDatasource(client: client),
        ),
      ),
      listPaymentsUsecase: ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      ),
      listVouchersUsecase: ListVouchersUsecase(
        repository: ListVouchersRepository(
          datasource: ListVouchersDatasource(client: client),
        ),
      ),
      createVoucherUsecase: CreateVoucherUsecase(
        repository: CreateVoucherRepository(
          datasource: CreateVoucherDatasource(client: client),
        ),
      ),
      revokeVoucherUsecase: RevokeVoucherUsecase(
        repository: RevokeVoucherRepository(
          datasource: RevokeVoucherDatasource(client: client),
        ),
      ),
      listVoucherRedemptionsUsecase: ListVoucherRedemptionsUsecase(
        repository: ListVoucherRedemptionsRepository(
          datasource: ListVoucherRedemptionsDatasource(client: client),
        ),
      ),
    );

    proto.Plan planoProto({int id = 1, bool active = true}) => proto.Plan(
      id: id,
      name: 'Pro',
      description: 'Plano Pro',
      price: '199.90',
      maxInstances: 3,
      maxDepartments: 5,
      active: active,
      createdAt: ms(DateTime(2026, 1, 1)),
    );

    void tresListasRespondem() {
      when(() => client.listPlans(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListPlansResponse(plans: [planoProto()])),
      );
      when(() => client.listSubscriptions(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListSubscriptionsResponse(
            subscriptions: [
              proto.Subscription(
                id: 1,
                tenantId: 't1',
                planId: 1,
                status: 'active',
                currentPeriodStart: ms(DateTime(2026, 1, 1)),
                currentPeriodEnd: ms(DateTime(2026, 2, 1)),
                paymentGateway: 'manual',
                updatedAt: ms(DateTime(2026, 1, 15)),
              ),
            ],
          ),
        ),
      );
      when(() => client.listPayments(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListPaymentsResponse(
            payments: [
              proto.PaymentRecord(
                id: 1,
                tenantId: 't1',
                amount: '199.90',
                paymentDate: '2026-01-05',
                paymentMethod: 'pix',
                periodStart: '2026-01-01',
                periodEnd: '2026-02-01',
                notes: '',
                recordedById: 9,
                createdAt: ms(DateTime(2026, 1, 5)),
              ),
            ],
          ),
        ),
      );
      // A carga única do painel também busca vouchers desde a migration 0027.
      when(() => client.listVouchers(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListVouchersResponse()),
      );
    }

    test('converte plano, assinatura e pagamento', () async {
      tresListasRespondem();

      final planos = await ListPlansUsecase(
        repository: ListPlansRepository(
          datasource: ListPlansDatasource(client: client),
        ),
      )(noParams);
      final assinaturas = await ListSubscriptionsUsecase(
        repository: ListSubscriptionsRepository(
          datasource: ListSubscriptionsDatasource(client: client),
        ),
      )(noParams);
      final pagamentos = await ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      )(const ListPaymentsParameters());

      expect((planos as Success).value.single.price, '199.90');
      expect((assinaturas as Success).value.single.status, 'active');
      expect((pagamentos as Success).value.single.paymentMethod, 'pix');
    });

    test('listPayments filtra por tenant quando informado', () async {
      tresListasRespondem();

      await ListPaymentsUsecase(
        repository: ListPaymentsRepository(
          datasource: ListPaymentsDatasource(client: client),
        ),
      )(const ListPaymentsParameters(tenantId: 't7'));

      final enviado =
          verify(() => client.listPayments(captureAny())).captured.single
              as proto.ListPaymentsRequest;
      expect(enviado.tenantId, 't7');
    });

    test('createPlan envia os limites do plano', () async {
      when(() => client.createPlan(any())).thenAnswer(
        (_) => respostaGrpc(proto.CreatePlanResponse(plan: planoProto())),
      );

      await CreatePlanUsecase(
        repository: CreatePlanRepository(
          datasource: CreatePlanDatasource(client: client),
        ),
      )(
        const CreatePlanParameters(
          name: 'Pro',
          description: 'd',
          price: '199.90',
          maxInstances: 3,
          maxDepartments: 5,
          maxFluxos: 7,
        ),
      );

      final enviado =
          verify(() => client.createPlan(captureAny())).captured.single
              as proto.CreatePlanRequest;
      expect(enviado.maxInstances, 3);
      expect(enviado.maxDepartments, 5);
    });

    test('registerPayment envia o período e devolve o registro', () async {
      when(() => client.registerPayment(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.RegisterPaymentResponse(
            payment: proto.PaymentRecord(
              id: 5,
              tenantId: 't1',
              amount: '99',
              paymentDate: '2026-01-05',
              paymentMethod: 'pix',
              periodStart: '2026-01-01',
              periodEnd: '2026-02-01',
              notes: 'ok',
              recordedById: 1,
              createdAt: ms(DateTime(2026, 1, 5)),
            ),
          ),
        ),
      );

      final r =
          await RegisterPaymentUsecase(
            repository: RegisterPaymentRepository(
              datasource: RegisterPaymentDatasource(client: client),
            ),
          )(
            const RegisterPaymentParameters(
              tenantId: 't1',
              amount: '99',
              paymentMethod: 'pix',
              paymentDate: '2026-01-05',
              periodStart: '2026-01-01',
              periodEnd: '2026-02-01',
              notes: 'ok',
            ),
          );

      expect((r as Success).value.id, 5);
      final enviado =
          verify(() => client.registerPayment(captureAny())).captured.single
              as proto.RegisterPaymentRequest;
      expect(enviado.periodStart, '2026-01-01');
    });

    blocTest<BillingController, ViewState<BillingState>>(
      'controller compõe as três listas numa única carga',
      build: () {
        tresListasRespondem();
        return controller();
      },
      act: (c) => c.fetchBillingData(),
      expect: () => [
        isA<LoadingState<BillingState>>(),
        isA<SuccessState<BillingState>>()
            .having((s) => s.data.plans, 'planos', hasLength(1))
            .having((s) => s.data.subscriptions, 'assinaturas', hasLength(1))
            .having((s) => s.data.payments, 'pagamentos', hasLength(1)),
      ],
    );

    blocTest<BillingController, ViewState<BillingState>>(
      'falha na primeira lista curto-circuita a carga',
      build: () {
        when(
          () => client.listPlans(any()),
        ).thenAnswer((_) => falhaGrpc(proto.GrpcError.permissionDenied('x')));
        return controller();
      },
      act: (c) => c.fetchBillingData(),
      expect: () => [
        isA<LoadingState<BillingState>>(),
        isA<ErrorState<BillingState>>().having(
          (s) => s.error,
          'erro',
          isA<BillingAcessoNegado>(),
        ),
      ],
      verify: (_) {
        // Não faz sentido buscar assinaturas se planos já falhou.
        verifyNever(() => client.listSubscriptions(any()));
      },
    );

    test('criar plano com sucesso recarrega as três listas', () async {
      tresListasRespondem();
      when(() => client.createPlan(any())).thenAnswer(
        (_) => respostaGrpc(proto.CreatePlanResponse(plan: planoProto())),
      );
      final c = controller();

      final r = await c.createPlan(
        name: 'Pro',
        description: 'd',
        price: '1',
        maxInstances: 1,
        maxDepartments: 1,
        maxFluxos: 1,
      );

      expect(r, isA<Success>());
      verify(() => client.listPlans(any())).called(1);
      await c.close();
    });

    test('atualizar plano com sucesso recarrega', () async {
      tresListasRespondem();
      when(() => client.updatePlan(any())).thenAnswer(
        (_) => respostaGrpc(proto.UpdatePlanResponse(success: true)),
      );
      final c = controller();

      final r = await c.updatePlan(
        id: 1,
        name: 'Pro',
        description: 'd',
        price: '1',
        maxInstances: 1,
        maxDepartments: 1,
        maxFluxos: 1,
        active: false,
      );

      expect(r, isA<Success>());
      verify(() => client.listPlans(any())).called(1);
      await c.close();
    });

    test('registrar pagamento com sucesso recarrega', () async {
      tresListasRespondem();
      when(() => client.registerPayment(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.RegisterPaymentResponse(
            payment: proto.PaymentRecord(
              id: 1,
              tenantId: 't1',
              amount: '1',
              paymentDate: 'd',
              paymentMethod: 'pix',
              periodStart: 'a',
              periodEnd: 'b',
              notes: '',
              recordedById: 1,
              createdAt: ms(DateTime(2026, 1, 1)),
            ),
          ),
        ),
      );
      final c = controller();

      final r = await c.registerPayment(
        tenantId: 't1',
        amount: '1',
        paymentMethod: 'pix',
        paymentDate: 'd',
        periodStart: 'a',
        periodEnd: 'b',
        notes: '',
      );

      expect(r, isA<Success>());
      verify(() => client.listPayments(any())).called(1);
      await c.close();
    });
  });

  // ── feature_flags ────────────────────────────────────────────────────────
  group('feature_flags', () {
    FeatureFlagsController controller() => FeatureFlagsController(
      listUsecase: ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      ),
      setUsecase: SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      ),
      setOverrideUsecase: SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      ),
      listTenantsUsecase: ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      ),
    );

    void flagsRespondem() =>
        when(() => client.listFeatureFlags(any())).thenAnswer(
          (_) => respostaGrpc(
            proto.ListFeatureFlagsResponse(
              flags: [
                proto.FeatureFlag(
                  key: 'ia_resposta_automatica',
                  description: 'Resposta automática da IA',
                  enabledGlobally: false,
                  overrides: [
                    proto.FeatureFlagOverride(tenantId: 't1', enabled: true),
                  ],
                ),
              ],
            ),
          ),
        );

    test('converte a flag com os overrides por tenant', () async {
      flagsRespondem();

      final r = await ListFeatureFlagsUsecase(
        repository: ListFeatureFlagsRepository(
          datasource: ListFeatureFlagsDatasource(client: client),
        ),
      )(noParams);

      final flag = (r as Success<List<FeatureFlag>, dynamic>).value.single;
      expect(flag.key, 'ia_resposta_automatica');
      expect(flag.enabledGlobally, isFalse);
      expect(flag.overrides.single.tenantId, 't1');
      expect(flag.overrides.single.enabled, isTrue);
    });

    test('setFeatureFlag envia a chave e o novo estado global', () async {
      when(() => client.setFeatureFlag(any())).thenAnswer(
        (_) => respostaGrpc(proto.SetFeatureFlagResponse(success: true)),
      );

      await SetFeatureFlagUsecase(
        repository: SetFeatureFlagRepository(
          datasource: SetFeatureFlagDatasource(client: client),
        ),
      )(const SetFeatureFlagParameters(key: 'k', enabledGlobally: true));

      final enviado =
          verify(() => client.setFeatureFlag(captureAny())).captured.single
              as proto.SetFeatureFlagRequest;
      expect(enviado.key, 'k');
      expect(enviado.enabledGlobally, isTrue);
    });

    test('remover override é sinalizado por removeOverride', () async {
      // Distinguir "desligar para o tenant" de "voltar ao valor global" é o que
      // a flag removeOverride resolve.
      when(() => client.setFeatureFlagOverride(any())).thenAnswer(
        (_) =>
            respostaGrpc(proto.SetFeatureFlagOverrideResponse(success: true)),
      );

      await SetFeatureFlagOverrideUsecase(
        repository: SetFeatureFlagOverrideRepository(
          datasource: SetFeatureFlagOverrideDatasource(client: client),
        ),
      )(
        const SetFeatureFlagOverrideParameters(
          key: 'k',
          tenantId: 't1',
          enabled: false,
          removeOverride: true,
        ),
      );

      final enviado =
          verify(
                () => client.setFeatureFlagOverride(captureAny()),
              ).captured.single
              as proto.SetFeatureFlagOverrideRequest;
      expect(enviado.removeOverride, isTrue);
      expect(enviado.enabled, isFalse);
    });

    blocTest<FeatureFlagsController, ViewState<List<FeatureFlag>>>(
      'controller carrega as flags',
      build: () {
        flagsRespondem();
        return controller();
      },
      act: (c) => c.fetchFeatureFlags(),
      expect: () => [
        isA<LoadingState<List<FeatureFlag>>>(),
        isA<SuccessState<List<FeatureFlag>>>().having(
          (s) => s.data,
          'flags',
          hasLength(1),
        ),
      ],
    );

    test('alterar flag com sucesso recarrega a lista', () async {
      flagsRespondem();
      when(() => client.setFeatureFlag(any())).thenAnswer(
        (_) => respostaGrpc(proto.SetFeatureFlagResponse(success: true)),
      );
      final c = controller();

      final r = await c.setFeatureFlag(key: 'k', enabledGlobally: true);

      expect(r, isA<Success>());
      verify(() => client.listFeatureFlags(any())).called(1);
      await c.close();
    });

    test('override com sucesso recarrega a lista', () async {
      flagsRespondem();
      when(() => client.setFeatureFlagOverride(any())).thenAnswer(
        (_) =>
            respostaGrpc(proto.SetFeatureFlagOverrideResponse(success: true)),
      );
      final c = controller();

      final r = await c.setFeatureFlagOverride(
        key: 'k',
        tenantId: 't1',
        enabled: true,
        removeOverride: false,
      );

      expect(r, isA<Success>());
      verify(() => client.listFeatureFlags(any())).called(1);
      await c.close();
    });

    test('getTenants devolve o erro da feature dona da operação', () async {
      // A lista de tenants pertence à feature tenants: a falha vem tipada como
      // TenantsError, não como FeatureFlagsError.
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListTenantsResponse(tenants: [])));
      final c = controller();

      final r = await c.getTenants();

      expect(r, isA<Success<List<Tenant>, dynamic>>());
      await c.close();
    });
  });

  // ── audit ────────────────────────────────────────────────────────────────
  group('audit', () {
    AuditController controller() => AuditController(
      queryUsecase: QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      ),
      exportUsecase: ExportTenantsCsvUsecase(
        repository: ExportTenantsCsvRepository(
          datasource: ExportTenantsCsvDatasource(client: client),
        ),
      ),
      listTenantsUsecase: ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      ),
    );

    void logResponde() => when(() => client.queryAuditLog(any())).thenAnswer(
      (_) => respostaGrpc(
        proto.QueryAuditLogResponse(
          totalCount: 1,
          entries: [
            proto.AuditLogEntry(
              id: 1,
              eventType: 'tenant.criado',
              actor: 'admin@x.com',
              tenantId: 't1',
              description: 'criou o tenant',
              ipAddress: '10.0.0.1',
              userAgent: 'Chrome',
              createdAt: ms(DateTime(2026, 1, 1, 10)),
            ),
          ],
        ),
      ),
    );

    test('converte a entrada de auditoria', () async {
      logResponde();

      final r = await QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      )(const QueryAuditLogParameters());

      final e = (r as Success<List<AuditLogEntry>, dynamic>).value.single;
      expect(e.eventType, 'tenant.criado');
      expect(e.actor, 'admin@x.com');
      expect(e.createdAt, DateTime(2026, 1, 1, 10));
    });

    test('repassa os filtros informados', () async {
      logResponde();

      await QueryAuditLogUsecase(
        repository: QueryAuditLogRepository(
          datasource: QueryAuditLogDatasource(client: client),
        ),
      )(
        const QueryAuditLogParameters(
          tenantId: 't9',
          eventType: 'login.falhou',
          limit: 25,
          offset: 50,
        ),
      );

      final enviado =
          verify(() => client.queryAuditLog(captureAny())).captured.single
              as proto.QueryAuditLogRequest;
      expect(enviado.tenantId, 't9');
      expect(enviado.eventType, 'login.falhou');
      expect(enviado.limit, 25);
      expect(enviado.offset, 50);
    });

    blocTest<AuditController, ViewState<List<AuditLogEntry>>>(
      'controller carrega o log',
      build: () {
        logResponde();
        return controller();
      },
      act: (c) => c.fetchAuditLogs(),
      expect: () => [
        isA<LoadingState<List<AuditLogEntry>>>(),
        isA<SuccessState<List<AuditLogEntry>>>().having(
          (s) => s.data,
          'entradas',
          hasLength(1),
        ),
      ],
    );

    test('exportTenantsCsv devolve os bytes concatenados', () async {
      when(() => client.exportTenantsCsv(any())).thenAnswer(
        (_) => streamGrpc([
          proto.ExportTenantsCsvResponse(chunk: [65]),
          proto.ExportTenantsCsvResponse(chunk: [66]),
        ]),
      );
      final c = controller();

      final r = await c.exportTenantsCsv();

      expect((r as Success).value, [65, 66]);
      await c.close();
    });
  });

  // ── evolution ────────────────────────────────────────────────────────────
  group('evolution', () {
    EvolutionController controller() => EvolutionController(
      listTenantsUsecase: ListTenantsUsecase(
        repository: ListTenantsRepository(
          datasource: ListTenantsDatasource(client: client),
        ),
      ),
      testConnectionUsecase: TestEvolutionConnectionUsecase(
        repository: TestEvolutionConnectionRepository(
          datasource: TestEvolutionConnectionDatasource(client: client),
        ),
      ),
    );

    test('conexão saudável devolve o status do provedor', () async {
      when(() => client.testEvolutionConnection(any())).thenAnswer(
        (_) =>
            respostaGrpc(proto.TestEvolutionConnectionResponse(status: 'open')),
      );
      final c = controller();

      final r = await c.testConnection('t1');

      expect((r as Success).value.status, 'open');
      await c.close();
    });

    test('instância com problema traz a mensagem do provedor', () async {
      when(() => client.testEvolutionConnection(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.TestEvolutionConnectionResponse(
            status: 'close',
            errorMessage: 'instancia desconectada',
          ),
        ),
      );
      final c = controller();

      final r = await c.testConnection('t1');

      final resultado = (r as Success).value;
      expect(resultado.status, 'close');
      expect(resultado.errorMessage, 'instancia desconectada');
      await c.close();
    });

    blocTest<EvolutionController, ViewState<List<Tenant>>>(
      'controller carrega os tenants para a tela de instâncias',
      build: () {
        when(() => client.listTenants(any())).thenAnswer(
          (_) => respostaGrpc(
            proto.ListTenantsResponse(
              tenants: [
                proto.Tenant(
                  id: 't1',
                  name: 'X',
                  slug: 'x',
                  apiKey: 'k',
                  ownerId: 1,
                  email: 'e@e.com',
                  phone: '1',
                  active: true,
                  createdAt: ms(DateTime(2026, 1, 1)),
                  updatedAt: ms(DateTime(2026, 1, 1)),
                ),
              ],
            ),
          ),
        );
        return controller();
      },
      act: (c) => c.fetchTenants(),
      expect: () => [
        isA<LoadingState<List<Tenant>>>(),
        isA<SuccessState<List<Tenant>>>().having(
          (s) => s.data,
          'tenants',
          hasLength(1),
        ),
      ],
    );
  });

  // ── dashboard ────────────────────────────────────────────────────────────
  group('dashboard', () {
    test('converte o resumo e a saúde dos serviços', () async {
      when(() => client.getDashboardSummary(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetDashboardSummaryResponse(
            totalTenants: 10,
            activeTenants: 8,
            totalSubscriptions: 6,
            monthlyRecurringRevenue: '1999.90',
            health: [
              proto.ServiceHealth(
                serviceName: 'data_postgres',
                status: 'up',
                message: 'ok',
                responseTimeMs: Int64(12),
              ),
            ],
          ),
        ),
      );

      final r = await GetDashboardSummaryUsecase(
        repository: GetDashboardSummaryRepository(
          datasource: GetDashboardSummaryDatasource(client: client),
        ),
      )(noParams);

      final s = (r as Success<DashboardSummary, dynamic>).value;
      expect(s.totalTenants, 10);
      expect(s.activeTenants, 8);
      expect(s.monthlyRecurringRevenue, '1999.90');
      expect(s.health.single.serviceName, 'data_postgres');
    });

    test('saúde dos serviços é lida em chamada própria', () async {
      when(() => client.getServiceHealth(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetServiceHealthResponse(
            services: [
              proto.ServiceHealth(
                serviceName: 'data_redis',
                status: 'degraded',
                message: 'latencia alta',
                responseTimeMs: Int64(300),
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

      final servico = (r as Success).value.single;
      expect(servico.status, 'degraded');
      expect(servico.responseTimeMs, 300);
    });

    blocTest<DashboardController, ViewState<DashboardSummary>>(
      'controller carrega o resumo',
      build: () {
        when(() => client.getDashboardSummary(any())).thenAnswer(
          (_) =>
              respostaGrpc(proto.GetDashboardSummaryResponse(totalTenants: 3)),
        );
        return DashboardController(
          getSummaryUsecase: GetDashboardSummaryUsecase(
            repository: GetDashboardSummaryRepository(
              datasource: GetDashboardSummaryDatasource(client: client),
            ),
          ),
        );
      },
      act: (c) => c.fetchSummary(),
      expect: () => [
        isA<LoadingState<DashboardSummary>>(),
        isA<SuccessState<DashboardSummary>>().having(
          (s) => s.data.totalTenants,
          'totalTenants',
          3,
        ),
      ],
    );
  });
}
