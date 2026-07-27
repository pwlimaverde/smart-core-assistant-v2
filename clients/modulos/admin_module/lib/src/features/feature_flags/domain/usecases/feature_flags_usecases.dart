import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../errors/feature_flags_errors.dart';
import '../model/feature_flag.dart';
import '../parameters/feature_flags_parameters.dart';

/// Casos de uso da feature `feature_flags`.
///
/// Os `process` são passthrough: a regra de negócio destas operações vive no
/// servidor (é o painel do superusuário). O que a base agrega aqui é o
/// `onUnexpected` — nenhuma exceção do processamento escapa para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de \$operacao quebrou',
      name: 'admin_module.feature_flags',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lista as flags e seus overrides por tenant.
final class ListFeatureFlagsUsecase
    extends
        UsecaseBaseCallData<
          List<FeatureFlag>,
          List<FeatureFlag>,
          NoParams,
          FeatureFlagsError
        > {
  const ListFeatureFlagsUsecase({required super.repository});

  @override
  ProcessData<List<FeatureFlag>, List<FeatureFlag>, NoParams, FeatureFlagsError>
  get process => _process;

  @override
  FeatureFlagsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listFeatureFlags', exception, stackTrace);
    return const FeatureFlagsInesperado();
  }

  static ReturnSuccessOrError<List<FeatureFlag>, FeatureFlagsError> _process(
    List<FeatureFlag> data,
    NoParams parameters,
  ) => Success(data);
}

/// Liga ou desliga uma flag globalmente.
final class SetFeatureFlagUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          SetFeatureFlagParameters,
          FeatureFlagsError
        > {
  const SetFeatureFlagUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, SetFeatureFlagParameters, FeatureFlagsError>
  get process => _process;

  @override
  FeatureFlagsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('setFeatureFlag', exception, stackTrace);
    return const FeatureFlagsInesperado();
  }

  static ReturnSuccessOrError<Unit, FeatureFlagsError> _process(
    Unit data,
    SetFeatureFlagParameters parameters,
  ) => Success(data);
}

/// Define ou remove o override de uma flag para um tenant.
final class SetFeatureFlagOverrideUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          SetFeatureFlagOverrideParameters,
          FeatureFlagsError
        > {
  const SetFeatureFlagOverrideUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, SetFeatureFlagOverrideParameters, FeatureFlagsError>
  get process => _process;

  @override
  FeatureFlagsError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('setFeatureFlagOverride', exception, stackTrace);
    return const FeatureFlagsInesperado();
  }

  static ReturnSuccessOrError<Unit, FeatureFlagsError> _process(
    Unit data,
    SetFeatureFlagOverrideParameters parameters,
  ) => Success(data);
}
