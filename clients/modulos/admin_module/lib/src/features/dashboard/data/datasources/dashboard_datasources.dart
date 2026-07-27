import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/dashboard_summary.dart';
import '../../domain/model/service_health.dart';

/// Datasources da feature `dashboard`: I/O gRPC e conversão protobuf →
/// domínio. Todos burros — sem `try/catch`, a exceção sobe crua para o
/// `mapError` do repositório correspondente.

/// Lê a saúde dos serviços do backend.
final class GetServiceHealthDatasource
    implements Datasource<List<ServiceHealth>, NoParams> {
  final proto.AdminServiceClient _client;

  const GetServiceHealthDatasource({required this._client});

  @override
  Future<List<ServiceHealth>> call(NoParams parameters) async {
    final resp = await _client.getServiceHealth(
      proto.GetServiceHealthRequest(),
    );
    return resp.services
        .map(
          (s) => ServiceHealth(
            serviceName: s.serviceName,
            status: s.status,
            message: s.message,
            responseTimeMs: s.responseTimeMs.toInt(),
          ),
        )
        .toList();
  }
}

/// Lê os números agregados do painel.
final class GetDashboardSummaryDatasource
    implements Datasource<DashboardSummary, NoParams> {
  final proto.AdminServiceClient _client;

  const GetDashboardSummaryDatasource({required this._client});

  @override
  Future<DashboardSummary> call(NoParams parameters) async {
    final resp = await _client.getDashboardSummary(
      proto.GetDashboardSummaryRequest(),
    );
    return DashboardSummary(
      totalTenants: resp.totalTenants,
      activeTenants: resp.activeTenants,
      totalSubscriptions: resp.totalSubscriptions,
      monthlyRecurringRevenue: resp.monthlyRecurringRevenue,
      health: resp.health
          .map(
            (s) => ServiceHealth(
              serviceName: s.serviceName,
              status: s.status,
              message: s.message,
              responseTimeMs: s.responseTimeMs.toInt(),
            ),
          )
          .toList(),
    );
  }
}
