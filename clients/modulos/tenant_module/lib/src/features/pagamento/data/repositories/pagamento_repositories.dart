import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/pagamento_errors.dart';
import '../../domain/model/quitacao.dart';
import '../../domain/parameters/pagamento_parameters.dart';

/// Fronteira da quitação.
///
/// O log registra **só a natureza da falha** — nunca a credencial, nem o
/// provedor com o código junto. Um voucher em log é um voucher distribuído.
final class QuitarAssinaturaRepository
    extends
        RepositoryBase<Quitacao, QuitarAssinaturaParameters, PagamentoError> {
  const QuitarAssinaturaRepository({required super.datasource});

  @override
  PagamentoError mapError(
    Object exception,
    StackTrace stackTrace,
    QuitarAssinaturaParameters parameters,
  ) {
    final kind = classificarFalhaGrpc(exception);
    developer.log(
      'quitarMinhaAssinatura falhou: $kind',
      name: 'tenant_module.pagamento',
      error: exception,
      stackTrace: stackTrace,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const PagamentoAcessoNegado(),
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition ||
      // `notFound`/`alreadyExists` não têm significado próprio aqui: a recusa
      // do código vem como sucesso com `confirmado: false`.
      GrpcFailureKind.notFound ||
      GrpcFailureKind.alreadyExists => const PagamentoDadosInvalidos(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const PagamentoIndisponivel(),
      GrpcFailureKind.unknown => const PagamentoInesperado(),
    };
  }
}
