import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/tenants_errors.dart';
import '../../domain/usecases/tenants_usecases.dart';
import '../../domain/parameters/tenants_parameters.dart';
import '../../domain/model/tenant.dart';

final class TenantsController extends BaseController<List<Tenant>> {
  final ListTenantsUsecase _listUsecase;
  final CreateTenantUsecase _createUsecase;
  final UpdateTenantUsecase _updateUsecase;
  final SetTenantActiveUsecase _setActiveUsecase;
  final GenerateAccessCodeUsecase _generateAccessCodeUsecase;

  TenantsController({
    required this._listUsecase,
    required this._createUsecase,
    required this._updateUsecase,
    required this._setActiveUsecase,
    required this._generateAccessCodeUsecase,
  });

  Future<void> fetchTenants() => execute(() => _listUsecase(noParams));

  Future<ReturnSuccessOrError<Tenant, TenantsError>> createTenant({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    final res = await _createUsecase(
      CreateTenantParameters(
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      ),
    );
    if (res is Success) {
      await fetchTenants();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit, TenantsError>> updateTenant({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    final res = await _updateUsecase(
      UpdateTenantParameters(
        id: id,
        name: name,
        slug: slug,
        ownerId: ownerId,
        email: email,
        phone: phone,
      ),
    );
    if (res is Success) {
      await fetchTenants();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit, TenantsError>> setTenantActive({
    required String id,
    required bool active,
  }) async {
    final res = await _setActiveUsecase(
      SetTenantActiveParameters(id: id, active: active),
    );
    if (res is Success) {
      await fetchTenants();
    }
    return res;
  }

  Future<ReturnSuccessOrError<String, TenantsError>> generateAccessCode(
    String id,
  ) async {
    return _generateAccessCodeUsecase(GenerateAccessCodeParameters(id: id));
  }
}
