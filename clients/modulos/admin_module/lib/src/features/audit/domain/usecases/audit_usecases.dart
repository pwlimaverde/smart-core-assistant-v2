import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/audit_errors.dart';
import '../model/audit_log_entry.dart';
import '../parameters/audit_parameters.dart';

/// Casos de uso da feature `audit`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.audit',
      error: exception,
      stackTrace: stackTrace,
    );

/// Consulta o log de auditoria com filtros.
final class QueryAuditLogUsecase
    extends
        UsecaseBaseCallData<
          List<AuditLogEntry>,
          List<AuditLogEntry>,
          QueryAuditLogParameters,
          AuditError
        > {
  const QueryAuditLogUsecase({required super.repository});

  @override
  ProcessData<
    List<AuditLogEntry>,
    List<AuditLogEntry>,
    QueryAuditLogParameters,
    AuditError
  >
  get process => _process;

  @override
  AuditError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('queryAuditLog', exception, stackTrace);
    return const AuditInesperado();
  }

  static ReturnSuccessOrError<List<AuditLogEntry>, AuditError> _process(
    List<AuditLogEntry> data,
    QueryAuditLogParameters parameters,
  ) => Success(data);
}
