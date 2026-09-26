import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/config_errors.dart';
import '../../domain/model/tenant_config.dart';
import '../../domain/parameters/config_parameters.dart';
import '../../domain/usecases/config_usecases.dart';

final class TenantOwnConfigController extends BaseController<TenantConfig> {
  final GetMyTenantConfigUsecase _getUsecase;
  final UpdateMyTenantConfigUsecase _updateUsecase;

  /// Opcional: onde não foi registrado, a tela não oferece a seção avançada.
  final UpdateConfigAvancadaUsecase? _updateAvancadaUsecase;

  TenantOwnConfigController({
    required this._getUsecase,
    required this._updateUsecase,
    this._updateAvancadaUsecase,
  });

  bool get podeEditarAvancada => _updateAvancadaUsecase != null;

  Future<ReturnSuccessOrError<Unit, TenantConfigError>> updateAvancada(
    ConfigAvancada avancada, {
    Set<String> promptsRemovidos = const {},
  }) async {
    final usecase = _updateAvancadaUsecase;
    if (usecase == null) return const Failure(ConfigInesperado());
    final res = await usecase(
      UpdateConfigAvancadaParameters(
        avancada: avancada,
        promptsRemovidos: promptsRemovidos,
      ),
    );
    if (res is Success) await fetchConfig();
    return res;
  }

  Future<void> fetchConfig() => execute(() => _getUsecase(noParams));

  Future<ReturnSuccessOrError<Unit, TenantConfigError>> updateConfig(
    TenantConfig config,
  ) async {
    final res = await _updateUsecase(
      UpdateMyTenantConfigParameters(config: config),
    );
    if (res is Success) await fetchConfig();
    return res;
  }
}
