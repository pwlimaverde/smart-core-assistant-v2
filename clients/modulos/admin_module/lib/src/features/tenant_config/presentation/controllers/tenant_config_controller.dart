import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/tenant_config_errors.dart';
import '../../domain/usecases/tenant_config_usecases.dart';
import '../../domain/parameters/tenant_config_parameters.dart';
import '../../domain/model/tenant_config.dart';

final class TenantConfigController extends BaseController<TenantConfig> {
  final GetTenantConfigUsecase _getUsecase;
  final UpdateTenantConfigUsecase _updateUsecase;
  final DefinirMotorUsecase? _motorUsecase;

  TenantConfigController({
    required this._getUsecase,
    required this._updateUsecase,
    this._motorUsecase,
  });

  /// Plano ia-engine-jev — troca o motor da IA do tenant. Devolve o texto
  /// para a tela ("llm → jev") ou o erro.
  Future<ReturnSuccessOrError<(String, String), TenantConfigError>>
  definirMotor({required String tenantId, required String motor}) async {
    final usecase = _motorUsecase;
    if (usecase == null) return const Failure(TenantConfigInesperado());
    return usecase(DefinirMotorParameters(tenantId: tenantId, motor: motor));
  }

  Future<void> fetchConfig(String tenantId) =>
      execute(() => _getUsecase(GetTenantConfigParameters(tenantId: tenantId)));

  Future<ReturnSuccessOrError<Unit, TenantConfigError>> updateConfig({
    required String tenantId,
    required TenantConfig config,
  }) async {
    final res = await _updateUsecase(
      UpdateTenantConfigParameters(tenantId: tenantId, config: config),
    );
    if (res is Success) {
      await fetchConfig(tenantId);
    }
    return res;
  }
}
