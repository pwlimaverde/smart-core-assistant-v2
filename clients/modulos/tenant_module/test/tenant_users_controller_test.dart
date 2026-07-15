import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/domain/model/tenant_config.dart';
import 'package:tenant_module/src/domain/model/tenant_invite.dart';
import 'package:tenant_module/src/domain/model/tenant_user.dart';
import 'package:tenant_module/src/domain/services/tenant_admin_service.dart';
import 'package:tenant_module/src/domain/usecases/list_tenant_users_usecase.dart';
import 'package:tenant_module/src/domain/usecases/update_tenant_user_usecase.dart';
import 'package:tenant_module/src/presentation/usuarios/controllers/tenant_users_controller.dart';

class _FakeTenantAdminService implements TenantAdminService {
  ReturnSuccessOrError<List<TenantUser>> listResult;
  ReturnSuccessOrError<Unit> updateResult;

  _FakeTenantAdminService({
    required this.listResult,
    this.updateResult = const SuccessReturn(success: unit),
  });

  @override
  Future<ReturnSuccessOrError<List<TenantUser>>> listTenantUsers() async => listResult;

  @override
  Future<ReturnSuccessOrError<Unit>> updateTenantUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) async => updateResult;

  @override
  Future<ReturnSuccessOrError<TenantInviteCreated>> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<List<TenantInvite>>> listInvites() => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<Unit>> revokeInvite(String inviteId) => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<AcceptedTenantUser>> acceptInvite({
    required String token,
    required String username,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<TenantConfig>> getMyTenantConfig() => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<Unit>> updateMyTenantConfig(TenantConfig config) =>
      throw UnimplementedError();
}

TenantUser _user({required int userId, String role = 'staff'}) => TenantUser(
      id: userId,
      userId: userId,
      role: role,
      modulePermissions: const ['atendimentos:read'],
      flowPermissions: const [1],
      isActive: true,
      createdAt: DateTime.now(),
    );

void main() {
  group('TenantUsersController.fetchUsers', () {
    blocTest<TenantUsersController, ViewState<List<TenantUser>>>(
      'sucesso: emite [Loading, Success] com os usuários',
      build: () {
        final service = _FakeTenantAdminService(
          listResult: SuccessReturn(success: [_user(userId: 1)]),
        );
        return TenantUsersController(
          listUsecase: ListTenantUsersUsecase(service: service),
          updateUsecase: UpdateTenantUserUsecase(service: service),
        );
      },
      act: (c) => c.fetchUsers(),
      expect: () => [
        isA<LoadingState<List<TenantUser>>>(),
        isA<SuccessState<List<TenantUser>>>()
            .having((s) => s.data.single.userId, 'userId', 1),
      ],
    );

    blocTest<TenantUsersController, ViewState<List<TenantUser>>>(
      'RBAC negado (sem tenant:admin): emite [Loading, Error]',
      build: () {
        final service = _FakeTenantAdminService(
          listResult: const ErrorReturn(error: ErrorUnauthorized(message: 'Acesso negado.')),
        );
        return TenantUsersController(
          listUsecase: ListTenantUsersUsecase(service: service),
          updateUsecase: UpdateTenantUserUsecase(service: service),
        );
      },
      act: (c) => c.fetchUsers(),
      expect: () => [
        isA<LoadingState<List<TenantUser>>>(),
        isA<ErrorState<List<TenantUser>>>(),
      ],
    );
  });

  group('TenantUsersController.updateUser', () {
    test('sucesso: recarrega a lista após atualizar role/escopos', () async {
      final service = _FakeTenantAdminService(
        listResult: SuccessReturn(success: [_user(userId: 1)]),
      );
      final controller = TenantUsersController(
        listUsecase: ListTenantUsersUsecase(service: service),
        updateUsecase: UpdateTenantUserUsecase(service: service),
      );
      await controller.fetchUsers();

      service.listResult = SuccessReturn(success: [_user(userId: 1, role: 'admin')]);
      final res = await controller.updateUser(userId: 1, role: 'admin');

      expect(res, isA<SuccessReturn<Unit>>());
      final estado = controller.state as SuccessState<List<TenantUser>>;
      expect(estado.data.single.role, 'admin');
      await controller.close();
    });

    test('RBAC negado (sem tenant:admin): propaga o erro sem recarregar', () async {
      final service = _FakeTenantAdminService(
        listResult: SuccessReturn(success: [_user(userId: 1)]),
        updateResult: const ErrorReturn(error: ErrorUnauthorized(message: 'Acesso negado.')),
      );
      final controller = TenantUsersController(
        listUsecase: ListTenantUsersUsecase(service: service),
        updateUsecase: UpdateTenantUserUsecase(service: service),
      );

      final res = await controller.updateUser(userId: 1, role: 'admin');

      expect(res, isA<ErrorReturn<Unit>>());
      await controller.close();
    });
  });
}
