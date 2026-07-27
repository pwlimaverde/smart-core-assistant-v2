import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/feature_flags_errors.dart';
import '../../domain/model/feature_flag.dart';
import '../../domain/parameters/feature_flags_parameters.dart';

/// Fronteiras da feature `feature_flags`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

FeatureFlagsError _mapFeatureFlags(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.feature_flags',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const FeatureFlagsAcessoNegado(),
    GrpcFailureKind.notFound => const FeatureFlagsNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const FeatureFlagsConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const FeatureFlagsDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const FeatureFlagsIndisponivel(),
    GrpcFailureKind.unknown => const FeatureFlagsInesperado(),
  };
}

final class ListFeatureFlagsRepository
    extends RepositoryBase<List<FeatureFlag>, NoParams, FeatureFlagsError> {
  const ListFeatureFlagsRepository({required super.datasource});

  @override
  FeatureFlagsError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapFeatureFlags('listFeatureFlags', exception, stackTrace);
}

final class SetFeatureFlagRepository
    extends RepositoryBase<Unit, SetFeatureFlagParameters, FeatureFlagsError> {
  const SetFeatureFlagRepository({required super.datasource});

  @override
  FeatureFlagsError mapError(
    Object exception,
    StackTrace stackTrace,
    SetFeatureFlagParameters parameters,
  ) => _mapFeatureFlags('setFeatureFlag', exception, stackTrace);
}

final class SetFeatureFlagOverrideRepository
    extends
        RepositoryBase<
          Unit,
          SetFeatureFlagOverrideParameters,
          FeatureFlagsError
        > {
  const SetFeatureFlagOverrideRepository({required super.datasource});

  @override
  FeatureFlagsError mapError(
    Object exception,
    StackTrace stackTrace,
    SetFeatureFlagOverrideParameters parameters,
  ) => _mapFeatureFlags('setFeatureFlagOverride', exception, stackTrace);
}
