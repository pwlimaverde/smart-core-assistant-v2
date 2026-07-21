import 'package:admin_module/src/features/config/domain/model/dashboard_summary.dart';
import 'package:admin_module/src/features/config/domain/model/feature_flag.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../support/fixtures.dart';

// Os modelos de dominio do admin_module sao data classes simples (campos +
// construtor const, sem serializacao). Estes testes apenas garantem que os
// construtores propagam os campos como esperado, inclusive os compostos
// (DashboardSummary -> ServiceHealth) e aninhados (FeatureFlag -> overrides).
void main() {
  test('Tenant expoe os campos do construtor', () {
    final tenant = tenantFixture(id: 'x', active: false);
    expect(tenant.id, 'x');
    expect(tenant.active, isFalse);
    expect(tenant.onboardingStep, 3);
    expect(tenant.updatedAt, DateTime(2026, 2, 1));
  });

  test('TenantConfig preserva o mapa de apiKeys', () {
    final config = tenantConfigFixture(apiKeys: const {'anthropic': 'sk-xyz'});
    expect(config.apiKeys['anthropic'], 'sk-xyz');
    expect(config.chunkSize, 512);
    expect(config.chunkOverlap, 64);
  });

  test('DashboardSummary agrega a lista de ServiceHealth', () {
    final summary = dashboardSummaryFixture();
    expect(summary, isA<DashboardSummary>());
    expect(summary.activeTenants, 8);
    expect(summary.health.single.serviceName, 'postgres');
    expect(summary.health.single.status, 'healthy');
  });

  test('FeatureFlag carrega os overrides aninhados', () {
    final flag = featureFlagFixture(key: 'beta');
    expect(flag, isA<FeatureFlag>());
    expect(flag.key, 'beta');
    expect(flag.enabledGlobally, isFalse);
    expect(flag.overrides.single.tenantId, 'tenant-1');
    expect(flag.overrides.single.enabled, isTrue);
  });

  test('Plan, Subscription e PaymentRecord propagam os campos', () {
    expect(planFixture(id: 9).id, 9);
    expect(subscriptionFixture(id: 3).planId, 1);
    final payment = paymentRecordFixture(id: 4);
    expect(payment.id, 4);
    expect(payment.recordedById, 42);
    expect(payment.paymentMethod, 'pix');
  });

  test('AuditLogEntry e EvolutionConnectionResult propagam os campos', () {
    expect(auditLogEntryFixture(id: 7).id, 7);
    expect(auditLogEntryFixture().eventType, 'tenant.created');
    expect(evolutionResultFixture(status: 'failed').status, 'failed');
    expect(coreSettingFixture(key: 'k').encrypted, isTrue);
  });
}
