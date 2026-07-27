// Fábricas de modelos de domínio reutilizadas pelos testes do admin_module.
// Cada helper devolve uma instância válida com valores determinísticos, para
// que os testes verifiquem propagação de dados sem repetir construtores longos.
import 'package:admin_module/src/features/audit/domain/model/audit_log_entry.dart';
import 'package:admin_module/src/features/core_settings/domain/model/core_setting.dart';
import 'package:admin_module/src/features/dashboard/domain/model/dashboard_summary.dart';
import 'package:admin_module/src/features/evolution/domain/model/evolution_connection_result.dart';
import 'package:admin_module/src/features/feature_flags/domain/model/feature_flag.dart';
import 'package:admin_module/src/features/billing/domain/model/payment_record.dart';
import 'package:admin_module/src/features/billing/domain/model/plan.dart';
import 'package:admin_module/src/features/dashboard/domain/model/service_health.dart';
import 'package:admin_module/src/features/billing/domain/model/subscription.dart';
import 'package:admin_module/src/features/tenants/domain/model/tenant.dart';
import 'package:admin_module/src/features/tenant_config/domain/model/tenant_config.dart';

CoreSetting coreSettingFixture({String key = 'openai_api_key'}) => CoreSetting(
  key: key,
  value: 'secreto',
  encrypted: true,
  description: 'Chave da OpenAI',
);

TenantConfig tenantConfigFixture({Map<String, String>? apiKeys}) =>
    TenantConfig(
      dadosEmpresa: 'Empresa X',
      personaBot: 'Assistente cordial',
      botAgentName: 'Aria',
      msgFallback: 'Nao entendi.',
      msgSemInfo: 'Sem informacao.',
      msgTransferencia: 'Transferindo.',
      llmClass: 'openai',
      model: 'gpt-4o',
      llmTemperature: '0.7',
      transcriptionProvider: 'openai',
      transcriptionModel: 'whisper-1',
      visionProvider: 'openai',
      visionModel: 'gpt-4o',
      embeddingsClass: 'openai',
      embeddingsModel: 'text-embedding-3-small',
      chunkSize: 512,
      chunkOverlap: 64,
      similarityThreshold: '0.8',
      vectorDistanceThreshold: '0.4',
      apiKeys: apiKeys ?? const {'openai': 'sk-123'},
    );

Tenant tenantFixture({String id = 'tenant-1', bool active = true}) => Tenant(
  id: id,
  name: 'Tenant $id',
  slug: 'tenant-$id',
  apiKey: 'api-key-$id',
  ownerId: 7,
  email: 'dono@$id.com',
  phone: '+5511999999999',
  active: active,
  setupCompleted: true,
  onboardingStep: 3,
  accessCode: 'ABC123',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 2, 1),
);

Plan planFixture({int id = 1, bool active = true}) => Plan(
  id: id,
  name: 'Plano Pro',
  description: 'Plano profissional',
  price: '199.90',
  maxInstances: 5,
  maxDepartments: 10,
  active: active,
  createdAt: DateTime(2026, 1, 1),
);

Subscription subscriptionFixture({int id = 1}) => Subscription(
  id: id,
  tenantId: 'tenant-1',
  planId: 1,
  status: 'active',
  currentPeriodStart: DateTime(2026, 1, 1),
  currentPeriodEnd: DateTime(2026, 2, 1),
  paymentGateway: 'stripe',
  externalCustomerId: 'cus_1',
  externalSubscriptionId: 'sub_1',
  updatedAt: DateTime(2026, 1, 15),
);

PaymentRecord paymentRecordFixture({int id = 1}) => PaymentRecord(
  id: id,
  tenantId: 'tenant-1',
  amount: '199.90',
  paymentDate: '2026-01-10',
  paymentMethod: 'pix',
  periodStart: '2026-01-01',
  periodEnd: '2026-02-01',
  notes: 'pagamento manual',
  recordedById: 42,
  createdAt: DateTime(2026, 1, 10),
);

EvolutionConnectionResult evolutionResultFixture({
  String status = 'connected',
}) => EvolutionConnectionResult(status: status, errorMessage: '');

FeatureFlag featureFlagFixture({String key = 'nova_ui'}) => FeatureFlag(
  key: key,
  description: 'Habilita a nova UI',
  enabledGlobally: false,
  overrides: const [FeatureFlagOverride(tenantId: 'tenant-1', enabled: true)],
);

AuditLogEntry auditLogEntryFixture({int id = 1}) => AuditLogEntry(
  id: id,
  eventType: 'tenant.created',
  actor: 'admin',
  tenantId: 'tenant-1',
  description: 'Tenant criado',
  ipAddress: '127.0.0.1',
  userAgent: 'test-agent',
  createdAt: DateTime(2026, 1, 1),
);

ServiceHealth serviceHealthFixture({String name = 'postgres'}) => ServiceHealth(
  serviceName: name,
  status: 'healthy',
  message: 'ok',
  responseTimeMs: 12,
);

DashboardSummary dashboardSummaryFixture() => DashboardSummary(
  totalTenants: 10,
  activeTenants: 8,
  totalSubscriptions: 6,
  monthlyRecurringRevenue: '1199.40',
  health: [serviceHealthFixture()],
);
