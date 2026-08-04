import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/painel_errors.dart';
import '../../domain/model/painel.dart';

final class CarregarPainelRepository
    extends RepositoryBase<Painel, NoParams, PainelError> {
  const CarregarPainelRepository({required super.datasource});

  @override
  PainelError mapError(Object e, StackTrace s, NoParams p) {
    final kind = classificarFalhaGrpc(e);
    developer.log(
      'carregar painel falhou: $kind',
      name: 'tenant_module.painel',
      error: e,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const PainelAcessoNegado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited ||
      GrpcFailureKind.notFound ||
      GrpcFailureKind.failedPrecondition ||
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.alreadyExists => const PainelIndisponivel(),
      GrpcFailureKind.unknown => const PainelInesperado(),
    };
  }
}
