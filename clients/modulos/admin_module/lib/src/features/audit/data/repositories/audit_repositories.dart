import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/audit_errors.dart';
import '../../domain/model/audit_log_entry.dart';
import '../../domain/parameters/audit_parameters.dart';

/// Fronteiras da feature `audit`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

AuditError _mapAudit(String operacao, Object exception, StackTrace stackTrace) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.audit',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const AuditAcessoNegado(),
    GrpcFailureKind.notFound => const AuditNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const AuditConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const AuditDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const AuditIndisponivel(),
    GrpcFailureKind.unknown => const AuditInesperado(),
  };
}

final class QueryAuditLogRepository
    extends
        RepositoryBase<
          List<AuditLogEntry>,
          QueryAuditLogParameters,
          AuditError
        > {
  const QueryAuditLogRepository({required super.datasource});

  @override
  AuditError mapError(
    Object exception,
    StackTrace stackTrace,
    QueryAuditLogParameters parameters,
  ) => _mapAudit('queryAuditLog', exception, stackTrace);
}
