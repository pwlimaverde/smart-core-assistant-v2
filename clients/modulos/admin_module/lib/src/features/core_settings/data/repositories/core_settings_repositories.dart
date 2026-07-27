import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/core_settings_errors.dart';
import '../../domain/model/core_setting.dart';
import '../../domain/parameters/core_settings_parameters.dart';

/// Fronteiras da feature `core_settings`.
///
/// A tradução é compartilhada: as operações são CRUD sobre o mesmo recurso e
/// têm o mesmo repertório de falha, então dividem um conjunto de erro e um
/// `mapError`. O log registra a natureza da falha e a operação.

CoreSettingsError _mapCoreSettings(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '\$operacao falhou: \$kind',
    name: 'admin_module.core_settings',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const CoreSettingsAcessoNegado(),
    GrpcFailureKind.notFound => const CoreSettingsNaoEncontrado(),
    GrpcFailureKind.alreadyExists => const CoreSettingsConflito(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const CoreSettingsDadosInvalidos(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const CoreSettingsIndisponivel(),
    GrpcFailureKind.unknown => const CoreSettingsInesperado(),
  };
}

final class ListCoreSettingsRepository
    extends RepositoryBase<List<CoreSetting>, NoParams, CoreSettingsError> {
  const ListCoreSettingsRepository({required super.datasource});

  @override
  CoreSettingsError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapCoreSettings('listCoreSettings', exception, stackTrace);
}

final class UpsertCoreSettingRepository
    extends
        RepositoryBase<Unit, UpsertCoreSettingParameters, CoreSettingsError> {
  const UpsertCoreSettingRepository({required super.datasource});

  @override
  CoreSettingsError mapError(
    Object exception,
    StackTrace stackTrace,
    UpsertCoreSettingParameters parameters,
  ) => _mapCoreSettings('upsertCoreSetting', exception, stackTrace);
}

final class DeleteCoreSettingRepository
    extends
        RepositoryBase<Unit, DeleteCoreSettingParameters, CoreSettingsError> {
  const DeleteCoreSettingRepository({required super.datasource});

  @override
  CoreSettingsError mapError(
    Object exception,
    StackTrace stackTrace,
    DeleteCoreSettingParameters parameters,
  ) => _mapCoreSettings('deleteCoreSetting', exception, stackTrace);
}
