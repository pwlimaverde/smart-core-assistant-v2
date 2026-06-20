import 'package:api_client/api_client.dart' as proto;
import 'package:domain_models/domain_models.dart';

import '../../domain/model/core_setting.dart';
import '../../domain/model/tenant_config.dart';
import '../../domain/model/tenant.dart';
import '../../domain/model/plan.dart';
import '../../domain/model/subscription.dart';
import '../../domain/model/payment_record.dart';
import '../../domain/model/evolution_connection_result.dart';
import '../../domain/model/feature_flag.dart';
import '../../domain/model/audit_log_entry.dart';
import '../../domain/model/service_health.dart';
import '../../domain/model/dashboard_summary.dart';
import '../grpc_error_mapper.dart';

abstract interface class AdminGrpcDatasource {
  Future<List<CoreSetting>> listCoreSettings();
  Future<void> upsertCoreSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  });
  Future<void> deleteCoreSetting(String key);
  
  Future<TenantConfig> getTenantConfig(String tenantId);
  Future<void> updateTenantConfig({
    required String tenantId,
    required TenantConfig config,
  });

  // --- Fase 2: Tenants ---
  Future<List<Tenant>> listTenants();
  Future<Tenant> getTenant(String id);
  Future<Tenant> createTenant({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  });
  Future<void> updateTenant({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  });
  Future<void> setTenantActive({
    required String id,
    required bool active,
  });
  Future<String> generateAccessCode(String id);

  // --- Fase 2: Billing ---
  Future<List<Plan>> listPlans();
  Future<Plan> createPlan({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  });
  Future<void> updatePlan({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  });
  Future<List<Subscription>> listSubscriptions();
  Future<PaymentRecord> registerPayment({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  });
  Future<List<PaymentRecord>> listPayments({String? tenantId});

  // --- Fase 3: Evolution Connection ---
  Future<EvolutionConnectionResult> testEvolutionConnection(String tenantId);

  // --- Fase 4: Feature Flags ---
  Future<List<FeatureFlag>> listFeatureFlags();
  Future<void> setFeatureFlag({required String key, required bool enabledGlobally});
  Future<void> setFeatureFlagOverride({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  });

  // --- Fase 5: Auditoria & Saúde ---
  Future<List<AuditLogEntry>> queryAuditLog({
    String? tenantId,
    String? eventType,
    int? limit,
    int? offset,
  });
  Future<List<ServiceHealth>> getServiceHealth();
  Future<DashboardSummary> getDashboardSummary();
  Future<List<int>> exportTenantsCsv();
}

final class AdminGrpcDatasourceImpl implements AdminGrpcDatasource {
  final proto.AdminServiceClient _client;

  const AdminGrpcDatasourceImpl({required this._client});

  @override
  Future<List<CoreSetting>> listCoreSettings() async {
    try {
      final resp = await _client.listCoreSettings(proto.ListCoreSettingsRequest());
      return resp.settings
          .map((s) => CoreSetting(
                key: s.key,
                value: s.value,
                encrypted: s.encrypted,
                description: s.description,
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> upsertCoreSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  }) async {
    try {
      await _client.upsertCoreSetting(proto.UpsertCoreSettingRequest(
        key: key,
        value: value,
        encrypted: encrypted,
        description: description,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> deleteCoreSetting(String key) async {
    try {
      await _client.deleteCoreSetting(proto.DeleteCoreSettingRequest(key: key));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<TenantConfig> getTenantConfig(String tenantId) async {
    try {
      final resp = await _client.getTenantConfig(proto.GetTenantConfigRequest(tenantId: tenantId));
      
      final apiKeys = <String, String>{};
      for (final entry in resp.apiKeys) {
        apiKeys[entry.key] = entry.value;
      }

      return TenantConfig(
        dadosEmpresa: resp.dadosEmpresa,
        personaBot: resp.personaBot,
        botAgentName: resp.botAgentName,
        msgFallback: resp.msgFallback,
        msgSemInfo: resp.msgSemInfo,
        msgTransferencia: resp.msgTransferencia,
        llmClass: resp.llmClass,
        model: resp.model,
        llmTemperature: resp.llmTemperature,
        transcriptionProvider: resp.transcriptionProvider,
        transcriptionModel: resp.transcriptionModel,
        visionProvider: resp.visionProvider,
        visionModel: resp.visionModel,
        embeddingsClass: resp.embeddingsClass,
        embeddingsModel: resp.embeddingsModel,
        chunkSize: resp.chunkSize,
        chunkOverlap: resp.chunkOverlap,
        similarityThreshold: resp.similarityThreshold,
        vectorDistanceThreshold: resp.vectorDistanceThreshold,
        apiKeys: apiKeys,
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> updateTenantConfig({
    required String tenantId,
    required TenantConfig config,
  }) async {
    try {
      final apiKeysProto = <proto.ApiKeyEntry>[];
      config.apiKeys.forEach((k, v) {
        apiKeysProto.add(proto.ApiKeyEntry(key: k, value: v));
      });

      await _client.updateTenantConfig(proto.UpdateTenantConfigRequest(
        tenantId: tenantId,
        dadosEmpresa: config.dadosEmpresa,
        personaBot: config.personaBot,
        botAgentName: config.botAgentName,
        msgFallback: config.msgFallback,
        msgSemInfo: config.msgSemInfo,
        msgTransferencia: config.msgTransferencia,
        llmClass: config.llmClass,
        model: config.model,
        llmTemperature: config.llmTemperature,
        transcriptionProvider: config.transcriptionProvider,
        transcriptionModel: config.transcriptionModel,
        visionProvider: config.visionProvider,
        visionModel: config.visionModel,
        embeddingsClass: config.embeddingsClass,
        embeddingsModel: config.embeddingsModel,
        chunkSize: config.chunkSize,
        chunkOverlap: config.chunkOverlap,
        similarityThreshold: config.similarityThreshold,
        vectorDistanceThreshold: config.vectorDistanceThreshold,
        apiKeys: apiKeysProto,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  // --- Fase 2: Tenants Implementation ---
  @override
  Future<List<Tenant>> listTenants() async {
    try {
      final resp = await _client.listTenants(proto.ListTenantsRequest());
      return resp.tenants
          .map((t) => Tenant(
                id: t.id,
                name: t.name,
                slug: t.slug,
                apiKey: t.apiKey,
                ownerId: t.ownerId,
                email: t.email,
                phone: t.phone,
                active: t.active,
                setupCompleted: t.setupCompleted,
                onboardingStep: t.onboardingStep,
                accessCode: t.accessCode,
                createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt()),
                updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<Tenant> getTenant(String id) async {
    try {
      final resp = await _client.getTenant(proto.GetTenantRequest(id: id));
      final t = resp.tenant;
      return Tenant(
        id: t.id,
        name: t.name,
        slug: t.slug,
        apiKey: t.apiKey,
        ownerId: t.ownerId,
        email: t.email,
        phone: t.phone,
        active: t.active,
        setupCompleted: t.setupCompleted,
        onboardingStep: t.onboardingStep,
        accessCode: t.accessCode,
        createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt()),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt.toInt()),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<Tenant> createTenant({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    try {
      final resp = await _client.createTenant(proto.CreateTenantRequest(
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      ));
      final t = resp.tenant;
      return Tenant(
        id: t.id,
        name: t.name,
        slug: t.slug,
        apiKey: t.apiKey,
        ownerId: t.ownerId,
        email: t.email,
        phone: t.phone,
        active: t.active,
        setupCompleted: t.setupCompleted,
        onboardingStep: t.onboardingStep,
        accessCode: t.accessCode,
        createdAt: DateTime.fromMillisecondsSinceEpoch(t.createdAt.toInt()),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(t.updatedAt.toInt()),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> updateTenant({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    try {
      await _client.updateTenant(proto.UpdateTenantRequest(
        id: id,
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> setTenantActive({
    required String id,
    required bool active,
  }) async {
    try {
      await _client.setTenantActive(proto.SetTenantActiveRequest(
        id: id,
        active: active,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<String> generateAccessCode(String id) async {
    try {
      final resp = await _client.generateAccessCode(proto.GenerateAccessCodeRequest(id: id));
      return resp.accessCode;
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  // --- Fase 2: Billing Implementation ---
  @override
  Future<List<Plan>> listPlans() async {
    try {
      final resp = await _client.listPlans(proto.ListPlansRequest());
      return resp.plans
          .map((p) => Plan(
                id: p.id,
                name: p.name,
                description: p.description,
                price: p.price,
                maxInstances: p.maxInstances,
                maxDepartments: p.maxDepartments,
                active: p.active,
                createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<Plan> createPlan({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  }) async {
    try {
      final resp = await _client.createPlan(proto.CreatePlanRequest(
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
      ));
      final p = resp.plan;
      return Plan(
        id: p.id,
        name: p.name,
        description: p.description,
        price: p.price,
        maxInstances: p.maxInstances,
        maxDepartments: p.maxDepartments,
        active: p.active,
        createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> updatePlan({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  }) async {
    try {
      await _client.updatePlan(proto.UpdatePlanRequest(
        id: id,
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
        active: active,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<Subscription>> listSubscriptions() async {
    try {
      final resp = await _client.listSubscriptions(proto.ListSubscriptionsRequest());
      return resp.subscriptions
          .map((s) => Subscription(
                id: s.id,
                tenantId: s.tenantId,
                planId: s.planId,
                status: s.status,
                currentPeriodStart: DateTime.fromMillisecondsSinceEpoch(s.currentPeriodStart.toInt()),
                currentPeriodEnd: DateTime.fromMillisecondsSinceEpoch(s.currentPeriodEnd.toInt()),
                paymentGateway: s.paymentGateway,
                externalCustomerId: s.externalCustomerId,
                externalSubscriptionId: s.externalSubscriptionId,
                updatedAt: DateTime.fromMillisecondsSinceEpoch(s.updatedAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<PaymentRecord> registerPayment({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  }) async {
    try {
      final resp = await _client.registerPayment(proto.RegisterPaymentRequest(
        tenantId: tenantId,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentDate: paymentDate,
        periodStart: periodStart,
        periodEnd: periodEnd,
        notes: notes,
      ));
      final p = resp.payment;
      return PaymentRecord(
        id: p.id,
        tenantId: p.tenantId,
        amount: p.amount,
        paymentDate: p.paymentDate,
        paymentMethod: p.paymentMethod,
        periodStart: p.periodStart,
        periodEnd: p.periodEnd,
        notes: p.notes,
        recordedById: p.recordedById,
        createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<PaymentRecord>> listPayments({String? tenantId}) async {
    try {
      final resp = await _client.listPayments(proto.ListPaymentsRequest(
        tenantId: tenantId ?? '',
      ));
      return resp.payments
          .map((p) => PaymentRecord(
                id: p.id,
                tenantId: p.tenantId,
                amount: p.amount,
                paymentDate: p.paymentDate,
                paymentMethod: p.paymentMethod,
                periodStart: p.periodStart,
                periodEnd: p.periodEnd,
                notes: p.notes,
                recordedById: p.recordedById,
                createdAt: DateTime.fromMillisecondsSinceEpoch(p.createdAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  // --- Fase 3: Evolution Connection Implementation ---
  @override
  Future<EvolutionConnectionResult> testEvolutionConnection(String tenantId) async {
    try {
      final resp = await _client.testEvolutionConnection(proto.TestEvolutionConnectionRequest(
        tenantId: tenantId,
      ));
      return EvolutionConnectionResult(
        status: resp.status,
        errorMessage: resp.errorMessage,
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  // --- Fase 4: Feature Flags Implementation ---
  @override
  Future<List<FeatureFlag>> listFeatureFlags() async {
    try {
      final resp = await _client.listFeatureFlags(proto.ListFeatureFlagsRequest());
      return resp.flags
          .map((f) => FeatureFlag(
                key: f.key,
                description: f.description,
                enabledGlobally: f.enabledGlobally,
                overrides: f.overrides
                    .map((o) => FeatureFlagOverride(
                          tenantId: o.tenantId,
                          enabled: o.enabled,
                        ))
                    .toList(),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> setFeatureFlag({required String key, required bool enabledGlobally}) async {
    try {
      await _client.setFeatureFlag(proto.SetFeatureFlagRequest(
        key: key,
        enabledGlobally: enabledGlobally,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<void> setFeatureFlagOverride({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  }) async {
    try {
      await _client.setFeatureFlagOverride(proto.SetFeatureFlagOverrideRequest(
        key: key,
        tenantId: tenantId,
        enabled: enabled,
        removeOverride: removeOverride,
      ));
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  // --- Fase 5: Auditoria & Saúde Implementation ---
  @override
  Future<List<AuditLogEntry>> queryAuditLog({
    String? tenantId,
    String? eventType,
    int? limit,
    int? offset,
  }) async {
    try {
      final resp = await _client.queryAuditLog(proto.QueryAuditLogRequest(
        tenantId: tenantId ?? '',
        eventType: eventType ?? '',
        limit: limit ?? 50,
        offset: offset ?? 0,
      ));
      return resp.entries
          .map((a) => AuditLogEntry(
                id: a.id,
                eventType: a.eventType,
                actor: a.actor,
                tenantId: a.tenantId,
                description: a.description,
                ipAddress: a.ipAddress,
                userAgent: a.userAgent,
                createdAt: DateTime.fromMillisecondsSinceEpoch(a.createdAt.toInt()),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<ServiceHealth>> getServiceHealth() async {
    try {
      final resp = await _client.getServiceHealth(proto.GetServiceHealthRequest());
      return resp.services
          .map((s) => ServiceHealth(
                serviceName: s.serviceName,
                status: s.status,
                message: s.message,
                responseTimeMs: s.responseTimeMs.toInt(),
              ))
          .toList();
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<DashboardSummary> getDashboardSummary() async {
    try {
      final resp = await _client.getDashboardSummary(proto.GetDashboardSummaryRequest());
      return DashboardSummary(
        totalTenants: resp.totalTenants,
        activeTenants: resp.activeTenants,
        totalSubscriptions: resp.totalSubscriptions,
        monthlyRecurringRevenue: resp.monthlyRecurringRevenue,
        health: resp.health
            .map((s) => ServiceHealth(
                  serviceName: s.serviceName,
                  status: s.status,
                  message: s.message,
                  responseTimeMs: s.responseTimeMs.toInt(),
                ))
            .toList(),
      );
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }

  @override
  Future<List<int>> exportTenantsCsv() async {
    try {
      final stream = _client.exportTenantsCsv(proto.ExportTenantsCsvRequest());
      final List<int> bytes = [];
      await for (final resp in stream) {
        bytes.addAll(resp.chunk);
      }
      return bytes;
    } on proto.GrpcError catch (e) {
      throw mapGrpcError(e, const ErrorNetwork());
    } catch (e) {
      throw ErrorNetwork(message: '$e');
    }
  }
}

