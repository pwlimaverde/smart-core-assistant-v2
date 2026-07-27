import 'package:flutter_test/flutter_test.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:admin_module/src/features/core_settings/domain/errors/core_settings_errors.dart';
import 'package:admin_module/src/features/core_settings/domain/usecases/core_settings_usecases.dart';
import 'package:admin_module/src/features/core_settings/domain/model/core_setting.dart';
import 'package:admin_module/src/features/core_settings/domain/parameters/core_settings_parameters.dart';

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
  group('onUnexpected da feature core_settings', () {
    test(
      'ListCoreSettingsUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = ListCoreSettingsUsecase(
          repository:
              _RepoQueLanca<List<CoreSetting>, NoParams, CoreSettingsError>(),
        );

        final r = await usecase(noParams);

        expect((r as Failure).error, isA<CoreSettingsInesperado>());
      },
    );

    test(
      'UpsertCoreSettingUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = UpsertCoreSettingUsecase(
          repository:
              _RepoQueLanca<
                Unit,
                UpsertCoreSettingParameters,
                CoreSettingsError
              >(),
        );

        final r = await usecase(
          const UpsertCoreSettingParameters(
            key: 'k',
            value: 'v',
            encrypted: false,
            description: 'd',
          ),
        );

        expect((r as Failure).error, isA<CoreSettingsInesperado>());
      },
    );

    test(
      'DeleteCoreSettingUsecase converte bug do repositório em erro previsto',
      () async {
        final usecase = DeleteCoreSettingUsecase(
          repository:
              _RepoQueLanca<
                Unit,
                DeleteCoreSettingParameters,
                CoreSettingsError
              >(),
        );

        final r = await usecase(const DeleteCoreSettingParameters(key: 'k'));

        expect((r as Failure).error, isA<CoreSettingsInesperado>());
      },
    );
  });
}
