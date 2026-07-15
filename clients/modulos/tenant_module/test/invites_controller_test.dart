import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/domain/model/tenant_config.dart';
import 'package:tenant_module/src/domain/model/tenant_invite.dart';
import 'package:tenant_module/src/domain/model/tenant_user.dart';
import 'package:tenant_module/src/domain/services/tenant_admin_service.dart';
import 'package:tenant_module/src/domain/usecases/create_invite_usecase.dart';
import 'package:tenant_module/src/domain/usecases/list_invites_usecase.dart';
import 'package:tenant_module/src/domain/usecases/revoke_invite_usecase.dart';
import 'package:tenant_module/src/presentation/convites/controllers/invites_controller.dart';

/// Fake do [TenantAdminService] parametrizável por teste — evita subir
/// gRPC/rede: só exercita a orquestração de estado do controller.
class _FakeTenantAdminService implements TenantAdminService {
  ReturnSuccessOrError<List<TenantInvite>> listResult;
  ReturnSuccessOrError<TenantInviteCreated> createResult;
  ReturnSuccessOrError<Unit> revokeResult;

  _FakeTenantAdminService({
    required this.listResult,
    this.createResult = const ErrorReturn(error: ErrorNetwork()),
    this.revokeResult = const SuccessReturn(success: unit),
  });

  @override
  Future<ReturnSuccessOrError<TenantInviteCreated>> createInvite({
    required String email,
    required String name,
    required String role,
    List<String> modulePermissions = const [],
    List<int> flowPermissions = const [],
  }) async => createResult;

  @override
  Future<ReturnSuccessOrError<List<TenantInvite>>> listInvites() async => listResult;

  @override
  Future<ReturnSuccessOrError<Unit>> revokeInvite(String inviteId) async => revokeResult;

  @override
  Future<ReturnSuccessOrError<AcceptedTenantUser>> acceptInvite({
    required String token,
    required String username,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<List<TenantUser>>> listTenantUsers() => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<Unit>> updateTenantUser({
    required int userId,
    String? role,
    List<String>? modulePermissions,
    List<int>? flowPermissions,
  }) => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<TenantConfig>> getMyTenantConfig() => throw UnimplementedError();

  @override
  Future<ReturnSuccessOrError<Unit>> updateMyTenantConfig(TenantConfig config) =>
      throw UnimplementedError();
}

TenantInvite _invite({required String id, bool used = false, bool revoked = false}) => TenantInvite(
      id: id,
      email: 'convidado@empresa.com',
      name: 'Convidado',
      role: 'staff',
      modulePermissions: const ['atendimentos:read'],
      flowPermissions: const [1, 2],
      expiresAt: DateTime.now().add(const Duration(days: 7)),
      used: used,
      revoked: revoked,
      createdAt: DateTime.now(),
    );

void main() {
  group('InvitesController.fetchInvites', () {
    blocTest<InvitesController, ViewState<List<TenantInvite>>>(
      'sucesso: emite [Loading, Success] com os convites',
      build: () {
        final service = _FakeTenantAdminService(
          listResult: SuccessReturn(success: [_invite(id: '1')]),
        );
        return InvitesController(
          listUsecase: ListInvitesUsecase(service: service),
          createUsecase: CreateInviteUsecase(service: service),
          revokeUsecase: RevokeInviteUsecase(service: service),
        );
      },
      act: (c) => c.fetchInvites(),
      expect: () => [
        isA<LoadingState<List<TenantInvite>>>(),
        isA<SuccessState<List<TenantInvite>>>()
            .having((s) => s.data.single.id, 'id', '1'),
      ],
    );

    blocTest<InvitesController, ViewState<List<TenantInvite>>>(
      'erro do backend: emite [Loading, Error]',
      build: () {
        final service = _FakeTenantAdminService(
          listResult: const ErrorReturn(error: ErrorUnauthorized()),
        );
        return InvitesController(
          listUsecase: ListInvitesUsecase(service: service),
          createUsecase: CreateInviteUsecase(service: service),
          revokeUsecase: RevokeInviteUsecase(service: service),
        );
      },
      act: (c) => c.fetchInvites(),
      expect: () => [
        isA<LoadingState<List<TenantInvite>>>(),
        isA<ErrorState<List<TenantInvite>>>(),
      ],
    );
  });

  group('InvitesController.revokeInvite', () {
    test('sucesso: recarrega a lista após revogar', () async {
      final service = _FakeTenantAdminService(
        listResult: SuccessReturn(success: [_invite(id: '1')]),
      );
      final controller = InvitesController(
        listUsecase: ListInvitesUsecase(service: service),
        createUsecase: CreateInviteUsecase(service: service),
        revokeUsecase: RevokeInviteUsecase(service: service),
      );
      await controller.fetchInvites();

      service.listResult = SuccessReturn(success: [_invite(id: '1', revoked: true)]);
      final res = await controller.revokeInvite('1');

      expect(res, isA<SuccessReturn<Unit>>());
      final estado = controller.state as SuccessState<List<TenantInvite>>;
      expect(estado.data.single.revoked, isTrue);
      await controller.close();
    });

    test('erro do backend (ex.: convite já expirado): propaga o erro', () async {
      final service = _FakeTenantAdminService(
        listResult: SuccessReturn(success: [_invite(id: '1')]),
        revokeResult: const ErrorReturn(error: ErrorValidation()),
      );
      final controller = InvitesController(
        listUsecase: ListInvitesUsecase(service: service),
        createUsecase: CreateInviteUsecase(service: service),
        revokeUsecase: RevokeInviteUsecase(service: service),
      );

      final res = await controller.revokeInvite('1');

      expect(res, isA<ErrorReturn<Unit>>());
      await controller.close();
    });
  });

  group('InvitesController.createInvite', () {
    test('sucesso: recarrega a lista após criar o convite', () async {
      final service = _FakeTenantAdminService(
        listResult: const SuccessReturn(success: []),
        createResult: SuccessReturn(
          success: TenantInviteCreated(
            id: '1',
            tenantId: 'tenant-1',
            email: 'convidado@empresa.com',
            name: 'Convidado',
            role: 'staff',
            token: 'token-abc',
            expiresAt: DateTime.now().add(const Duration(days: 7)),
            used: false,
            createdAt: DateTime.now(),
          ),
        ),
      );
      final controller = InvitesController(
        listUsecase: ListInvitesUsecase(service: service),
        createUsecase: CreateInviteUsecase(service: service),
        revokeUsecase: RevokeInviteUsecase(service: service),
      );

      service.listResult = SuccessReturn(success: [_invite(id: '1')]);
      final res = await controller.createInvite(email: 'convidado@empresa.com', name: 'Convidado', role: 'staff');

      expect(res, isA<SuccessReturn<TenantInviteCreated>>());
      final estado = controller.state as SuccessState<List<TenantInvite>>;
      expect(estado.data.single.id, '1');
      await controller.close();
    });
  });
}
