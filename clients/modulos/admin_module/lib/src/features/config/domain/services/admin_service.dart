import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/core_setting.dart';
import '../model/tenant_config.dart';
import '../model/tenant.dart';
import '../model/plan.dart';
import '../model/subscription.dart';
import '../model/payment_record.dart';
import '../model/evolution_connection_result.dart';
import '../model/feature_flag.dart';
import '../model/audit_log_entry.dart';
import '../model/service_health.dart';
import '../model/dashboard_summary.dart';

abstract interface class AdminService {
  Future<ReturnSuccessOrError<List<CoreSetting>>> listCoreSettings();
  Future<ReturnSuccessOrError<Unit>> upsertCoreSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  });
  Future<ReturnSuccessOrError<Unit>> deleteCoreSetting(String key);
  
  Future<ReturnSuccessOrError<TenantConfig>> getTenantConfig(String tenantId);
  Future<ReturnSuccessOrError<Unit>> updateTenantConfig({
    required String tenantId,
    required TenantConfig config,
  });

  // --- Fase 2: Tenants ---
  Future<ReturnSuccessOrError<List<Tenant>>> listTenants();
  Future<ReturnSuccessOrError<Tenant>> getTenant(String id);
  Future<ReturnSuccessOrError<Tenant>> createTenant({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  });
  Future<ReturnSuccessOrError<Unit>> updateTenant({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  });
  Future<ReturnSuccessOrError<Unit>> setTenantActive({
    required String id,
    required bool active,
  });
  Future<ReturnSuccessOrError<String>> generateAccessCode(String id);

  // --- Fase 2: Billing ---
  Future<ReturnSuccessOrError<List<Plan>>> listPlans();
  Future<ReturnSuccessOrError<Plan>> createPlan({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  });
  Future<ReturnSuccessOrError<Unit>> updatePlan({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  });
  Future<ReturnSuccessOrError<List<Subscription>>> listSubscriptions();
  Future<ReturnSuccessOrError<PaymentRecord>> registerPayment({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  });
  Future<ReturnSuccessOrError<List<PaymentRecord>>> listPayments({String? tenantId});

  // --- Fase 3: Evolution Connection ---
  Future<ReturnSuccessOrError<EvolutionConnectionResult>> testEvolutionConnection(String tenantId);

  // --- Fase 4: Feature Flags ---
  Future<ReturnSuccessOrError<List<FeatureFlag>>> listFeatureFlags();
  Future<ReturnSuccessOrError<Unit>> setFeatureFlag({required String key, required bool enabledGlobally});
  Future<ReturnSuccessOrError<Unit>> setFeatureFlagOverride({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  });

  // --- Fase 5: Auditoria & Saúde ---
  Future<ReturnSuccessOrError<List<AuditLogEntry>>> queryAuditLog({
    String? tenantId,
    String? eventType,
    int? limit,
    int? offset,
  });
  Future<ReturnSuccessOrError<List<ServiceHealth>>> getServiceHealth();
  Future<ReturnSuccessOrError<DashboardSummary>> getDashboardSummary();
  Future<ReturnSuccessOrError<List<int>>> exportTenantsCsv();
}

