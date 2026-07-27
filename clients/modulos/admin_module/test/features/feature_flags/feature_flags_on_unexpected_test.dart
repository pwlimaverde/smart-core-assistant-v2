import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/feature_flags/domain/errors/feature_flags_errors.dart';
import 'package:admin_module/src/features/feature_flags/domain/usecases/feature_flags_usecases.dart';
import 'package:admin_module/src/features/feature_flags/domain/model/feature_flag.dart';
import 'package:admin_module/src/features/feature_flags/domain/parameters/feature_flags_parameters.dart';

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
  group('onUnexpected da feature feature_flags', () {
    test(
      'ListFeatureFlagsUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ListFeatureFlagsUsecase(
          repository:
              _RepoQueLanca<List<FeatureFlag>, NoParams, FeatureFlagsError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<FeatureFlagsInesperado>());
      },
    );

    test(
      'SetFeatureFlagUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = SetFeatureFlagUsecase(
          repository:
              _RepoQueLanca<
                Unit,
                SetFeatureFlagParameters,
                FeatureFlagsError
              >(),
        );

        final r = await usecase(
          const SetFeatureFlagParameters(key: 'k', enabledGlobally: true),
        );

        expect((r as Failure).error, isA<FeatureFlagsInesperado>());
      },
    );

    test(
      'SetFeatureFlagOverrideUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = SetFeatureFlagOverrideUsecase(
          repository:
              _RepoQueLanca<
                Unit,
                SetFeatureFlagOverrideParameters,
                FeatureFlagsError
              >(),
        );

        final r = await usecase(
          const SetFeatureFlagOverrideParameters(
            key: 'k',
            tenantId: 't1',
            enabled: true,
            removeOverride: false,
          ),
        );

        expect((r as Failure).error, isA<FeatureFlagsInesperado>());
      },
    );
  });
}
