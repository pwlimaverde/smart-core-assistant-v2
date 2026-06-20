import 'service_health.dart';

final class DashboardSummary {
  final int totalTenants;
  final int activeTenants;
  final int totalSubscriptions;
  final String monthlyRecurringRevenue;
  final List<ServiceHealth> health;

  const DashboardSummary({
    required this.totalTenants,
    required this.activeTenants,
    required this.totalSubscriptions,
    required this.monthlyRecurringRevenue,
    required this.health,
  });
}
