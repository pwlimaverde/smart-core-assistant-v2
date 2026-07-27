import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/audit/domain/errors/audit_errors.dart';
import 'package:admin_module/src/features/audit/domain/usecases/audit_usecases.dart';
import 'package:admin_module/src/features/audit/domain/model/audit_log_entry.dart';
import 'package:admin_module/src/features/audit/domain/parameters/audit_parameters.dart';

/// Repositório que quebra o contrato: lança em vez de devolver `Failure`.
///
/// A base do usecase protege o chamador disso convertendo via
/// `onUnexpected` — é a garantia central da lib, e a única forma de
/// exercitá-la é com uma implementação manual fora do contrato.
final class _RepoQueLanca<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    throw StateError('repositorio fora do contrato');
  }
}

void main() {
  group('onUnexpected da feature audit', () {
    test(
      'QueryAuditLogUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = QueryAuditLogUsecase(
          repository:
              _RepoQueLanca<
                List<AuditLogEntry>,
                QueryAuditLogParameters,
                AuditError
              >(),
        );

        final r = await usecase(const QueryAuditLogParameters());

        expect((r as Failure).error, isA<AuditInesperado>());
      },
    );
  });
}
