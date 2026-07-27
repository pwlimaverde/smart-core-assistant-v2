import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/dashboard_errors.dart';
import '../../domain/model/dashboard_summary.dart';
import '../../domain/model/service_health.dart';

/// Fronteiras da feature `dashboard`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

DashboardError _mapDashboard(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.dashboard',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const DashboardAcessoNegado(),
    GrpcFailureKind.notFound => const DashboardNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const DashboardConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const DashboardDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const DashboardIndisponivel(),
    GrpcFailureKind.unknown => const DashboardInesperado(),
  };
}

final class GetServiceHealthRepository
    extends RepositoryBase<List<ServiceHealth>, NoParams, DashboardError> {
  const GetServiceHealthRepository({required super.datasource});

  @override
  DashboardError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapDashboard('getServiceHealth', exception, stackTrace);
}

final class GetDashboardSummaryRepository
    extends RepositoryBase<DashboardSummary, NoParams, DashboardError> {
  const GetDashboardSummaryRepository({required super.datasource});

  @override
  DashboardError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapDashboard('getDashboardSummary', exception, stackTrace);
}
