import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant.dart';
import '../../domain/usecases/list_tenants_usecase.dart';
import '../../domain/usecases/create_tenant_usecase.dart';
import '../../domain/usecases/update_tenant_usecase.dart';
import '../../domain/usecases/set_tenant_active_usecase.dart';
import '../../domain/usecases/generate_access_code_usecase.dart';

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

  Future<void> fetchTenants() => execute(() => _listUsecase.call());

  Future<ReturnSuccessOrError<Tenant>> createTenant({
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    final res = await _createUsecase.call(
      name: name,
      slug: slug,
      ownerId: ownerId,
      email: email,
      phone: phone,
    );
    if (res is SuccessReturn<Tenant>) {
      await fetchTenants();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit>> updateTenant({
    required String id,
    required String name,
    required String slug,
    required int ownerId,
    required String email,
    required String phone,
  }) async {
    final res = await _updateUsecase.call(
      id: id,
      name: name,
      slug: slug,
      ownerId: ownerId,
      email: email,
      phone: phone,
    );
    if (res is SuccessReturn<Unit>) {
      await fetchTenants();
    }
    return res;
  }

  Future<ReturnSuccessOrError<Unit>> setTenantActive({
    required String id,
    required bool active,
  }) async {
    final res = await _setActiveUsecase.call(id: id, active: active);
    if (res is SuccessReturn<Unit>) {
      await fetchTenants();
    }
    return res;
  }

  Future<ReturnSuccessOrError<String>> generateAccessCode(String id) async {
    return _generateAccessCodeUsecase.call(id);
  }
}
