import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/dashboard_errors.dart';
import '../model/dashboard_summary.dart';
import '../model/service_health.dart';

/// Casos de uso da feature `dashboard`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.dashboard',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lê a saúde dos serviços do backend.
final class GetServiceHealthUsecase
    extends
        UsecaseBaseCallData<
          List<ServiceHealth>,
          List<ServiceHealth>,
          NoParams,
          DashboardError
        > {
  const GetServiceHealthUsecase({required super.repository});

  @override
  ProcessData<
    List<ServiceHealth>,
    List<ServiceHealth>,
    NoParams,
    DashboardError
  >
  get process => _process;

  @override
  DashboardError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getServiceHealth', exception, stackTrace);
    return const DashboardInesperado();
  }

  static ReturnSuccessOrError<List<ServiceHealth>, DashboardError> _process(
    List<ServiceHealth> data,
    NoParams parameters,
  ) => Success(data);
}

/// Lê os números agregados do painel.
final class GetDashboardSummaryUsecase
    extends
        UsecaseBaseCallData<
          DashboardSummary,
          DashboardSummary,
          NoParams,
          DashboardError
        > {
  const GetDashboardSummaryUsecase({required super.repository});

  @override
  ProcessData<DashboardSummary, DashboardSummary, NoParams, DashboardError>
  get process => _process;

  @override
  DashboardError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getDashboardSummary', exception, stackTrace);
    return const DashboardInesperado();
  }

  static ReturnSuccessOrError<DashboardSummary, DashboardError> _process(
    DashboardSummary data,
    NoParams parameters,
  ) => Success(data);
}
