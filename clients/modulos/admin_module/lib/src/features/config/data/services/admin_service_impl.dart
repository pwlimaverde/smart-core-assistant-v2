import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

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
import '../../domain/services/admin_service.dart';
import '../datasources/admin_grpc_datasource.dart';

final class AdminServiceImpl implements AdminService {
  final AdminGrpcDatasource _datasource;

  const AdminServiceImpl({required this._datasource});

  @override
  Future<ReturnSuccessOrError<List<CoreSetting>>> listCoreSettings() async {
    try {
      final res = await _datasource.listCoreSettings();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> upsertCoreSetting({
    required String key,
    required String value,
    required bool encrypted,
    required String description,
  }) async {
    try {
      await _datasource.upsertCoreSetting(
        key: key,
        value: value,
        encrypted: encrypted,
        description: description,
      );
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> deleteCoreSetting(String key) async {
    try {
      await _datasource.deleteCoreSetting(key);
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<TenantConfig>> getTenantConfig(String tenantId) async {
    try {
      final res = await _datasource.getTenantConfig(tenantId);
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> updateTenantConfig({
    required String tenantId,
    required TenantConfig config,
  }) async {
    try {
      await _datasource.updateTenantConfig(tenantId: tenantId, config: config);
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  // --- Fase 2: Tenants Implementation ---
  @override
  Future<ReturnSuccessOrError<List<Tenant>>> listTenants() async {
    try {
      final res = await _datasource.listTenants();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Tenant>> getTenant(String id) async {
    try {
      final res = await _datasource.getTenant(id);
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Tenant>> createTenant({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    try {
      final res = await _datasource.createTenant(
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      );
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> updateTenant({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    try {
      await _datasource.updateTenant(
        id: id,
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      );
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> setTenantActive({
    required String id,
    required bool active,
  }) async {
    try {
      await _datasource.setTenantActive(id: id, active: active);
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<String>> generateAccessCode(String id) async {
    try {
      final res = await _datasource.generateAccessCode(id);
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  // --- Fase 2: Billing Implementation ---
  @override
  Future<ReturnSuccessOrError<List<Plan>>> listPlans() async {
    try {
      final res = await _datasource.listPlans();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Plan>> createPlan({
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
  }) async {
    try {
      final res = await _datasource.createPlan(
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
      );
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> updatePlan({
    required int id,
    required String name,
    required String description,
    required String price,
    required int maxInstances,
    required int maxDepartments,
    required bool active,
  }) async {
    try {
      await _datasource.updatePlan(
        id: id,
        name: name,
        description: description,
        price: price,
        maxInstances: maxInstances,
        maxDepartments: maxDepartments,
        active: active,
      );
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<Subscription>>> listSubscriptions() async {
    try {
      final res = await _datasource.listSubscriptions();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<PaymentRecord>> registerPayment({
    required String tenantId,
    required String amount,
    required String paymentMethod,
    required String paymentDate,
    required String periodStart,
    required String periodEnd,
    required String notes,
  }) async {
    try {
      final res = await _datasource.registerPayment(
        tenantId: tenantId,
        amount: amount,
        paymentMethod: paymentMethod,
        paymentDate: paymentDate,
        periodStart: periodStart,
        periodEnd: periodEnd,
        notes: notes,
      );
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<PaymentRecord>>> listPayments({String? tenantId}) async {
    try {
      final res = await _datasource.listPayments(tenantId: tenantId);
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  // --- Fase 3: Evolution Connection ---
  @override
  Future<ReturnSuccessOrError<EvolutionConnectionResult>> testEvolutionConnection(String tenantId) async {
    try {
      final res = await _datasource.testEvolutionConnection(tenantId);
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  // --- Fase 4: Feature Flags ---
  @override
  Future<ReturnSuccessOrError<List<FeatureFlag>>> listFeatureFlags() async {
    try {
      final res = await _datasource.listFeatureFlags();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> setFeatureFlag({required String key, required bool enabledGlobally}) async {
    try {
      await _datasource.setFeatureFlag(key: key, enabledGlobally: enabledGlobally);
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> setFeatureFlagOverride({
    required String key,
    required String tenantId,
    required bool enabled,
    required bool removeOverride,
  }) async {
    try {
      await _datasource.setFeatureFlagOverride(
        key: key,
        tenantId: tenantId,
        enabled: enabled,
        removeOverride: removeOverride,
      );
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  // --- Fase 5: Auditoria & Saúde ---
  @override
  Future<ReturnSuccessOrError<List<AuditLogEntry>>> queryAuditLog({
    String? tenantId,
    String? eventType,
    int? limit,
    int? offset,
  }) async {
    try {
      final res = await _datasource.queryAuditLog(
        tenantId: tenantId,
        eventType: eventType,
        limit: limit,
        offset: offset,
      );
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<ServiceHealth>>> getServiceHealth() async {
    try {
      final res = await _datasource.getServiceHealth();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<DashboardSummary>> getDashboardSummary() async {
    try {
      final res = await _datasource.getDashboardSummary();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<int>>> exportTenantsCsv() async {
    try {
      final res = await _datasource.exportTenantsCsv();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }
}
