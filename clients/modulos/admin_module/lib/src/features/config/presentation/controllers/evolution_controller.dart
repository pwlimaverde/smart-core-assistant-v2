import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import '../../domain/model/tenant.dart';
import '../../domain/model/evolution_connection_result.dart';
import '../../domain/usecases/list_tenants_usecase.dart';
import '../../domain/usecases/test_evolution_connection_usecase.dart';

final class EvolutionController extends BaseController<List<Tenant>> {
  final ListTenantsUsecase _listTenantsUsecase;
  final TestEvolutionConnectionUsecase _testConnectionUsecase;

  EvolutionController({
    required this._listTenantsUsecase,
    required this._testConnectionUsecase,
  });

  Future<void> fetchTenants() => execute(() => _listTenantsUsecase.call());

  Future<ReturnSuccessOrError<EvolutionConnectionResult>> testConnection(String tenantId) async {
    return _testConnectionUsecase.call(tenantId);
  }
}
