import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/errors/evolution_errors.dart';
import '../../domain/usecases/evolution_usecases.dart';
import '../../domain/parameters/evolution_parameters.dart';
import '../../../tenants/domain/model/tenant.dart';
import '../../../tenants/domain/usecases/tenants_usecases.dart';
import '../../domain/model/evolution_connection_result.dart';

final class EvolutionController extends BaseController<List<Tenant>> {
  final ListTenantsUsecase _listTenantsUsecase;
  final TestEvolutionConnectionUsecase _testConnectionUsecase;

  /// P9 — opcional para não quebrar quem monta o controller sem ele.
  final TestarProvedorIaUsecase? _testarIa;

  EvolutionController({
    required this._listTenantsUsecase,
    required this._testConnectionUsecase,
    TestarProvedorIaUsecase? testarIa,
  }) : _testarIa = testarIa;

  /// P9 — ensaia o provedor de IA do tenant.
  Future<ReturnSuccessOrError<TesteProvedorIa, EvolutionError>> testarIa(
    String tenantId,
  ) async {
    final usecase = _testarIa;
    if (usecase == null) return const Failure(EvolutionInesperado());
    return usecase(TestarProvedorIaParameters(tenantId: tenantId));
  }

  Future<void> fetchTenants() => execute(() => _listTenantsUsecase(noParams));

  Future<ReturnSuccessOrError<EvolutionConnectionResult, EvolutionError>>
  testConnection(String tenantId) async {
    return _testConnectionUsecase(
      TestEvolutionConnectionParameters(tenantId: tenantId),
    );
  }
}
