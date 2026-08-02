import 'package:admin_module/src/features/billing/data/datasources/billing_datasources.dart';
import 'package:admin_module/src/features/billing/data/repositories/billing_repositories.dart';
import 'package:admin_module/src/features/billing/domain/usecases/billing_usecases.dart';
import 'package:admin_module/src/features/billing/presentation/controllers/billing_controller.dart';
import 'package:admin_module/src/features/billing/presentation/pages/billing_page.dart';
import 'package:admin_module/src/features/core_settings/data/datasources/core_settings_datasources.dart';
import 'package:admin_module/src/features/core_settings/data/repositories/core_settings_repositories.dart';
import 'package:admin_module/src/features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'package:admin_module/src/features/core_settings/presentation/controllers/core_settings_controller.dart';
import 'package:admin_module/src/features/core_settings/presentation/pages/core_settings_page.dart';
import 'package:admin_module/src/features/dashboard/data/datasources/dashboard_datasources.dart';
import 'package:admin_module/src/features/dashboard/data/repositories/dashboard_repositories.dart';
import 'package:admin_module/src/features/dashboard/domain/usecases/dashboard_usecases.dart';
import 'package:admin_module/src/features/dashboard/presentation/controllers/dashboard_controller.dart';
import 'package:admin_module/src/features/dashboard/presentation/pages/dashboard_page.dart';
import 'package:admin_module/src/features/evolution/data/datasources/evolution_datasources.dart';
import 'package:admin_module/src/features/evolution/data/repositories/evolution_repositories.dart';
import 'package:admin_module/src/features/evolution/domain/usecases/evolution_usecases.dart';
import 'package:admin_module/src/features/evolution/presentation/controllers/evolution_controller.dart';
import 'package:admin_module/src/features/evolution/presentation/pages/evolution_page.dart';
import 'package:admin_module/src/features/feature_flags/data/datasources/feature_flags_datasources.dart';
import 'package:admin_module/src/features/feature_flags/data/repositories/feature_flags_repositories.dart';
import 'package:admin_module/src/features/feature_flags/domain/usecases/feature_flags_usecases.dart';
import 'package:admin_module/src/features/feature_flags/presentation/controllers/feature_flags_controller.dart';
import 'package:admin_module/src/features/feature_flags/presentation/pages/feature_flags_page.dart';
import 'package:admin_module/src/features/tenant_config/data/datasources/tenant_config_datasources.dart';
import 'package:admin_module/src/features/tenant_config/data/repositories/tenant_config_repositories.dart';
import 'package:admin_module/src/features/tenant_config/domain/usecases/tenant_config_usecases.dart';
import 'package:admin_module/src/features/tenant_config/presentation/controllers/tenant_config_controller.dart';
import 'package:admin_module/src/features/tenant_config/presentation/pages/tenant_config_page.dart';
import 'package:admin_module/src/features/tenants/data/datasources/tenants_datasources.dart';
import 'package:admin_module/src/features/tenants/data/repositories/tenants_repositories.dart';
import 'package:admin_module/src/features/tenants/domain/usecases/tenants_usecases.dart';
import 'package:admin_module/src/features/tenants/presentation/controllers/tenants_controller.dart';
import 'package:admin_module/src/features/tenants/presentation/pages/tenants_page.dart';
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:design_system_module/design_system_module.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../support/admin_grpc_mock.dart';

/// Renderização das páginas do painel.
///
/// **A `AuditPage` está fora daqui de propósito:** ela importa
/// `dart:js_interop` para disparar o download do CSV no browser, e uma
/// biblioteca `js_interop` não carrega na VM do `flutter test` — o mesmo limite
/// já documentado em `api_client/test/src/grpc_api_client_test.dart`. Testá-la
/// exigiria `flutter test --platform chrome`, que não faz parte da esteira. O
/// comportamento dela é coberto pelo `AuditController` em `restantes_test.dart`.
///
/// São ~3.000 linhas que nenhum teste carregava: a política de cobertura antiga
/// excluía `presentation/pages` do denominador, então elas nem apareciam no
/// número. Cada teste aqui monta a página com o controller real (sobre o stub
/// gRPC mockado) e confere o que a tela promete ao operador — título, estado
/// vazio, dado carregado e a mensagem de erro quando o servidor recusa.
void main() {
  late MockAdminClient client;
  final getIt = GetIt.instance;

  setUpAll(registrarFallbacksDoAdmin);

  setUp(() {
    client = MockAdminClient();
  });

  tearDown(() => getIt.reset());

  /// Monta a página com viewport largo (as telas do painel são desktop-first e
  /// estouram o layout no tamanho default do teste) e **dentro de um GoRouter**:
  /// o `AdminDrawer` lê `matchedLocation` para marcar o item ativo, e três
  /// páginas leem o tenant do query param. Sem o roteador, o build lança
  /// `GoError: There is no GoRouterState above the current context`.
  Future<void> montar(
    WidgetTester tester,
    Widget pagina, {
    String rota = '/',
  }) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final router = GoRouter(
      initialLocation: rota,
      routes: [GoRoute(path: '/', builder: (_, _) => pagina)],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pump();
  }

  group('DashboardPage', () {
    void registrar() {
      getIt.registerSingleton<DashboardController>(
        DashboardController(
          getSummaryUsecase: GetDashboardSummaryUsecase(
            repository: GetDashboardSummaryRepository(
              datasource: GetDashboardSummaryDatasource(client: client),
            ),
          ),
        ),
      );
    }

    testWidgets('mostra os números do painel quando a carga conclui', (
      tester,
    ) async {
      when(() => client.getDashboardSummary(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetDashboardSummaryResponse(
            totalTenants: 12,
            activeTenants: 9,
            totalSubscriptions: 7,
            monthlyRecurringRevenue: '2500.00',
          ),
        ),
      );
      registrar();

      await montar(tester, const DashboardPage());
      await tester.pumpAndSettle();

      expect(find.text('Dashboard Geral'), findsOneWidget);
      expect(find.textContaining('12'), findsWidgets);
    });

    testWidgets('mostra a mensagem de erro quando o acesso é negado', (
      tester,
    ) async {
      when(() => client.getDashboardSummary(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('nao superuser')),
      );
      registrar();

      await montar(tester, const DashboardPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('superusuário'), findsWidgets);
    });
  });

  group('TenantsPage', () {
    void registrar() {
      getIt.registerSingleton<TenantsController>(
        TenantsController(
          listUsecase: ListTenantsUsecase(
            repository: ListTenantsRepository(
              datasource: ListTenantsDatasource(client: client),
            ),
          ),
          createUsecase: CreateTenantUsecase(
            repository: CreateTenantRepository(
              datasource: CreateTenantDatasource(client: client),
            ),
          ),
          updateUsecase: UpdateTenantUsecase(
            repository: UpdateTenantRepository(
              datasource: UpdateTenantDatasource(client: client),
            ),
          ),
          setActiveUsecase: SetTenantActiveUsecase(
            repository: SetTenantActiveRepository(
              datasource: SetTenantActiveDatasource(client: client),
            ),
          ),
          generateAccessCodeUsecase: GenerateAccessCodeUsecase(
            repository: GenerateAccessCodeRepository(
              datasource: GenerateAccessCodeDatasource(client: client),
            ),
          ),
        ),
      );
    }

    testWidgets('lista os tenants carregados', (tester) async {
      when(() => client.listTenants(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListTenantsResponse(
            tenants: [
              proto.Tenant(
                id: 't1',
                name: 'Empresa Alfa',
                slug: 'alfa',
                apiKey: 'k',
                ownerId: 1,
                email: 'alfa@x.com',
                phone: '11999',
                active: true,
                createdAt: ms(DateTime(2026, 1, 1)),
                updatedAt: ms(DateTime(2026, 1, 1)),
              ),
            ],
          ),
        ),
      );
      registrar();

      await montar(tester, const TenantsPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('Empresa Alfa'), findsWidgets);
    });

    testWidgets('o diálogo de novo tenant valida e envia o formulário', (
      tester,
    ) async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListTenantsResponse()));
      when(() => client.createTenant(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateTenantResponse(
            tenant: proto.Tenant(
              id: 't9',
              name: 'Nova',
              slug: 'nova',
              apiKey: 'k',
              ownerId: 4,
              email: 'nova@x.com',
              phone: '11555',
              active: true,
              createdAt: ms(DateTime(2026, 1, 1)),
              updatedAt: ms(DateTime(2026, 1, 1)),
            ),
          ),
        ),
      );
      registrar();

      await montar(tester, const TenantsPage());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Novo Tenant'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      final campos = find.byType(TextField);
      await tester.enterText(campos.at(0), 'Nova');
      await tester.enterText(campos.at(1), 'nova');
      await tester.enterText(campos.at(2), '4');
      await tester.enterText(campos.at(3), 'nova@x.com');
      await tester.enterText(campos.at(4), '11555');
      await tester.pump();

      await tester.tap(find.text('Salvar'));
      await tester.pumpAndSettle();

      verify(() => client.createTenant(any())).called(1);
    });

    testWidgets('erro de permissão aparece na tela', (tester) async {
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.permissionDenied('x')));
      registrar();

      await montar(tester, const TenantsPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('superusuário'), findsWidgets);
    });
  });

  group('CoreSettingsPage', () {
    void registrar() {
      getIt.registerSingleton<CoreSettingsController>(
        CoreSettingsController(
          listUsecase: ListCoreSettingsUsecase(
            repository: ListCoreSettingsRepository(
              datasource: ListCoreSettingsDatasource(client: client),
            ),
          ),
          upsertUsecase: UpsertCoreSettingUsecase(
            repository: UpsertCoreSettingRepository(
              datasource: UpsertCoreSettingDatasource(client: client),
            ),
          ),
          deleteUsecase: DeleteCoreSettingUsecase(
            repository: DeleteCoreSettingRepository(
              datasource: DeleteCoreSettingDatasource(client: client),
            ),
          ),
        ),
      );
    }

    testWidgets('lista as configurações globais', (tester) async {
      when(() => client.listCoreSettings(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListCoreSettingsResponse(
            settings: [
              proto.CoreSetting(
                key: 'openai_api_key',
                value: '****',
                encrypted: true,
                description: 'Chave da OpenAI',
              ),
            ],
          ),
        ),
      );
      registrar();

      await montar(tester, const CoreSettingsPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('openai_api_key'), findsWidgets);
    });
  });

  group('BillingPage', () {
    void registrar() {
      getIt.registerSingleton<BillingController>(
        BillingController(
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
        ),
      );
    }

    testWidgets('mostra os planos carregados', (tester) async {
      when(() => client.listPlans(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListPlansResponse(
            plans: [
              proto.Plan(
                id: 1,
                name: 'Plano Pro',
                description: 'd',
                price: '199.90',
                maxInstances: 3,
                maxDepartments: 5,
                active: true,
                createdAt: ms(DateTime(2026, 1, 1)),
              ),
            ],
          ),
        ),
      );
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListSubscriptionsResponse()));
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListPaymentsResponse()));
      when(
        () => client.listVouchers(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListVouchersResponse()));
      registrar();

      await montar(tester, const BillingPage());
      await tester.pumpAndSettle();

      // A tela é organizada em abas; a de Planos é a inicial.
      expect(find.text('Faturamento & Planos'), findsOneWidget);
      expect(find.text('Planos'), findsWidgets);
      expect(find.text('Assinaturas'), findsWidgets);
      expect(find.textContaining('Plano Pro'), findsWidgets);

      // As outras duas abas têm builders próprios: sem visitá-las, metade da
      // tela nunca é construída.
      await tester.tap(find.text('Assinaturas'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Histórico Financeiro'));
      await tester.pumpAndSettle();

      expect(find.text('Registrar Pagamento Manual'), findsWidgets);
    });

    testWidgets('a aba de vouchers lista os códigos com a situação', (
      tester,
    ) async {
      when(() => client.listPlans(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListPlansResponse()),
      );
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListSubscriptionsResponse()));
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListPaymentsResponse()));
      when(() => client.listVouchers(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListVouchersResponse(
            vouchers: [
              proto.Voucher(
                id: 'v-1',
                codigo: 'DEVTESTE',
                descricao: 'campanha de testes',
                planId: 1,
                planName: 'Básico',
                duracaoDias: 180,
                maxResgates: 0,
                resgatesUsados: 2,
                validoDe: ms(DateTime(2026, 1, 1)),
                createdAt: ms(DateTime(2026, 1, 1)),
              ),
            ],
          ),
        ),
      );
      registrar();

      await montar(tester, const BillingPage());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Vouchers'));
      await tester.pumpAndSettle();

      expect(find.text('DEVTESTE'), findsOneWidget);
      // `max_resgates = 0` é ilimitado — a tela precisa dizer isso, e não "0".
      expect(find.textContaining('ilimitado'), findsOneWidget);
    });

    testWidgets('editar e salvar um plano fecha a janela', (tester) async {
      // Regressão: o diálogo de edição era aberto com o `BuildContext` do item
      // do ListView. Salvar recarrega a lista e desmonta esse item, então o
      // `context.mounted` de depois do await era falso e o `Navigator.pop`
      // nunca rodava — o plano era gravado e a janela ficava aberta, sem erro
      // visível.
      // Com atraso, e não `respostaGrpc`: uma resposta que resolve na microtask
      // seguinte faz `LoadingState` e `SuccessState` caírem no mesmo frame, e a
      // lista nunca chega a ser desmontada — o teste passaria mesmo com o bug.
      // O que reproduz a condição real é a latência da rede.
      when(() => client.listPlans(any())).thenAnswer(
        (_) => FakeResponseFuture(
          Future.delayed(
            const Duration(milliseconds: 50),
            () => proto.ListPlansResponse(
              plans: [
                proto.Plan(
                  id: 1,
                  name: 'Plano Pro',
                  description: 'd',
                  price: '199.90',
                  maxInstances: 3,
                  maxDepartments: 5,
                  maxFluxos: 7,
                  active: true,
                  createdAt: ms(DateTime(2026, 1, 1)),
                ),
              ],
            ),
          ),
        ),
      );
      when(
        () => client.listSubscriptions(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListSubscriptionsResponse()));
      when(
        () => client.listPayments(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListPaymentsResponse()));
      when(
        () => client.listVouchers(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListVouchersResponse()));
      when(() => client.updatePlan(any())).thenAnswer(
        (_) => respostaGrpc(proto.UpdatePlanResponse(success: true)),
      );
      registrar();

      await montar(tester, const BillingPage());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.edit));
      await tester.pumpAndSettle();
      expect(find.text('Editar Plano'), findsOneWidget);

      await tester.tap(find.text('Salvar'));
      await tester.pump();
      await tester.pump();

      // A recarga troca a lista por um indicador de carregamento: é aqui que o
      // item do ListView — e o context que abriu o diálogo — deixa de existir.
      // Esta asserção fixa o mecanismo do bug, não só o sintoma.
      expect(find.byIcon(Icons.edit), findsNothing);
      await tester.pumpAndSettle();

      expect(find.text('Editar Plano'), findsNothing);
      // O limite de fluxos precisa ir junto: o servidor grava o que recebe.
      final enviado =
          verify(() => client.updatePlan(captureAny())).captured.single
              as proto.UpdatePlanRequest;
      expect(enviado.maxFluxos, 7);
    });
  });

  group('FeatureFlagsPage', () {
    void registrar() {
      getIt.registerSingleton<FeatureFlagsController>(
        FeatureFlagsController(
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
        ),
      );
    }

    testWidgets('lista as flags com o estado global', (tester) async {
      when(() => client.listFeatureFlags(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListFeatureFlagsResponse(
            flags: [
              proto.FeatureFlag(
                key: 'ia_resposta_automatica',
                description: 'Resposta automática',
                enabledGlobally: true,
              ),
            ],
          ),
        ),
      );
      when(
        () => client.listTenants(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListTenantsResponse()));
      registrar();

      await montar(tester, const FeatureFlagsPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('ia_resposta_automatica'), findsWidgets);
    });
  });

  group('EvolutionPage', () {
    void registrar() {
      getIt.registerSingleton<EvolutionController>(
        EvolutionController(
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
        ),
      );
    }

    testWidgets('lista os tenants para testar instâncias', (tester) async {
      when(() => client.listTenants(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListTenantsResponse(
            tenants: [
              proto.Tenant(
                id: 't1',
                name: 'Empresa Beta',
                slug: 'beta',
                apiKey: 'k',
                ownerId: 1,
                email: 'beta@x.com',
                phone: '1',
                active: true,
                createdAt: ms(DateTime(2026, 1, 1)),
                updatedAt: ms(DateTime(2026, 1, 1)),
              ),
            ],
          ),
        ),
      );
      registrar();

      await montar(tester, const EvolutionPage());
      await tester.pumpAndSettle();

      expect(find.textContaining('Empresa Beta'), findsWidgets);
    });
  });

  group('TenantConfigPage', () {
    void registrar() {
      getIt.registerSingleton<TenantConfigController>(
        TenantConfigController(
          getUsecase: GetTenantConfigUsecase(
            repository: GetTenantConfigRepository(
              datasource: GetTenantConfigDatasource(client: client),
            ),
          ),
          updateUsecase: UpdateTenantConfigUsecase(
            repository: UpdateTenantConfigRepository(
              datasource: UpdateTenantConfigDatasource(client: client),
            ),
          ),
        ),
      );
    }

    testWidgets('abre com o formulário de busca por tenant', (tester) async {
      // A tela pede o tenant por um campo de texto: sem id informado ela nasce
      // no estado inicial, sem disparar RPC.
      registrar();

      await montar(tester, const TenantConfigPage());
      await tester.pumpAndSettle();

      expect(find.text('Configurações por Tenant'), findsOneWidget);
      expect(find.byType(AppTextField), findsWidgets);
      verifyNever(() => client.getTenantConfig(any()));
    });
  });
}
