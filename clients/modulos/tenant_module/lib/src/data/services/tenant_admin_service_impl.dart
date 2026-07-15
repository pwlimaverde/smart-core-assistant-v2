import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/tenant_config.dart';
import '../../domain/model/tenant_invite.dart';
import '../../domain/model/tenant_user.dart';
import '../../domain/services/tenant_admin_service.dart';
import '../datasources/tenant_admin_grpc_datasource.dart';

final class TenantAdminServiceImpl implements TenantAdminService {
  final TenantAdminDataSource _datasource;

  const TenantAdminServiceImpl({required this._datasource});

  @override
  Future<ReturnSuccessOrError<TenantInviteCreated>> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) async {
    try {
      final res = await _datasource.createInvite(
        email: email,
        name: name,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      );
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<TenantInvite>>> listInvites() async {
    try {
      final res = await _datasource.listInvites();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> revokeInvite(String inviteId) async {
    try {
      await _datasource.revokeInvite(inviteId);
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<AcceptedTenantUser>> acceptInvite({
    required String token,
    required String username,
    required String email,
    required String password,
  }) async {
    try {
      final res = await _datasource.acceptInvite(
        token: token,
        username: username,
        email: email,
        password: password,
      );
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<List<TenantUser>>> listTenantUsers() async {
    try {
      final res = await _datasource.listTenantUsers();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> updateTenantUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) async {
    try {
      await _datasource.updateTenantUser(
        userId: userId,
        role: role,
        modulePermissions: modulePermissions,
        flowPermissions: flowPermissions,
      );
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<TenantConfig>> getMyTenantConfig() async {
    try {
      final res = await _datasource.getMyTenantConfig();
      return SuccessReturn(success: res);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }

  @override
  Future<ReturnSuccessOrError<Unit>> updateMyTenantConfig(TenantConfig config) async {
    try {
      await _datasource.updateMyTenantConfig(config);
      return const SuccessReturn(success: unit);
    } on AppError catch (e) {
      return ErrorReturn(error: e);
    } catch (e) {
      return ErrorReturn(error: ErrorNetwork(message: '$e'));
    }
  }
}
