import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/usuarios/data/datasources/usuarios_datasources.dart';
import 'package:tenant_module/src/features/usuarios/data/repositories/usuarios_repositories.dart';
import 'package:tenant_module/src/features/usuarios/domain/errors/usuarios_errors.dart';
import 'package:tenant_module/src/features/usuarios/domain/model/tenant_user.dart';
import 'package:tenant_module/src/features/usuarios/domain/parameters/usuarios_parameters.dart';
import 'package:tenant_module/src/features/usuarios/domain/usecases/usuarios_usecases.dart';
import 'package:tenant_module/src/features/usuarios/presentation/controllers/tenant_users_controller.dart';

import '../../support/admin_client_mock.dart';

({ListTenantUsersUsecase list, UpdateTenantUserUsecase update}) _usecases(
  MockAdminClient client,
) => (
  list: ListTenantUsersUsecase(
    repository: ListTenantUsersRepository(
      datasource: ListTenantUsersDatasource(client: client),
    ),
  ),
  update: UpdateTenantUserUsecase(
    repository: UpdateTenantUserRepository(
      datasource: UpdateTenantUserDatasource(client: client),
    ),
  ),
);

TenantUsersController _controller(MockAdminClient client) {
  final u = _usecases(client);
  return TenantUsersController(listUsecase: u.list, updateUsecase: u.update);
}

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoTenant);
  setUp(() => client = MockAdminClient());

  void listaResponde(List<proto.TenantUserItem> itens) =>
      when(() => client.listTenantUsers(any())).thenAnswer(
        (_) => respostaGrpc(proto.ListTenantUsersResponse(users: itens)),
      );

  group('ListTenantUsers', () {
    test('converte os itens do protobuf', () async {
      listaResponde([
        usuarioItemProto(
          id: 3,
          userId: 30,
          role: 'gestor',
          modulePermissions: const ['tenant:admin'],
          flowPermissions: const [1, 2],
        ),
      ]);

      final r = await _usecases(client).list(noParams);

      final u =
          (r as Success<List<TenantUser>, TenantUsuariosError>).value.single;
      expect(u.id, 3);
      expect(u.userId, 30);
      expect(u.role, 'gestor');
      expect(u.modulePermissions, ['tenant:admin']);
      expect(u.flowPermissions, [1, 2]);
      expect(u.createdAt, DateTime(2026, 1, 1));
    });

    test('ativos primeiro; dentro do grupo, os mais antigos antes', () async {
      listaResponde([
        usuarioItemProto(
          id: 1,
          isActive: false,
          createdAt: DateTime(2026, 1, 1),
        ),
        usuarioItemProto(
          id: 2,
          isActive: true,
          createdAt: DateTime(2026, 3, 1),
        ),
        usuarioItemProto(
          id: 3,
          isActive: true,
          createdAt: DateTime(2026, 2, 1),
        ),
      ]);

      final r = await _usecases(client).list(noParams);

      expect((r as Success).value.map((u) => u.id).toList(), [3, 2, 1]);
    });

    test('lista devolvida é imutável', () async {
      listaResponde([usuarioItemProto()]);

      final r = await _usecases(client).list(noParams);

      expect(
        () => ((r as Success).value as List<TenantUser>).clear(),
        throwsUnsupportedError,
      );
    });

    test('sem permissão vira acesso negado', () async {
      when(() => client.listTenantUsers(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      final erro = ((await _usecases(client).list(noParams)) as Failure).error;

      expect(erro, isA<UsuariosAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
    });
  });

  group('UpdateTenantUser', () {
    test(
      'campo null vira flag set_* falsa (preserva o valor no servidor)',
      () async {
        // É o que impede a UI de apagar permissões que ela nem exibiu.
        when(
          () => client.updateTenantUser(any()),
        ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantUserResponse()));

        await _usecases(
          client,
        ).update(const UpdateTenantUserParameters(userId: 10, role: 'gestor'));

        final enviado =
            verify(() => client.updateTenantUser(captureAny())).captured.single
                as proto.UpdateTenantUserRequest;
        expect(enviado.userId, 10);
        expect(enviado.setRole, isTrue);
        expect(enviado.role, 'gestor');
        expect(enviado.setModulePermissions, isFalse);
        expect(enviado.setFlowPermissions, isFalse);
      },
    );

    test(
      'lista vazia explícita LIMPA as permissões (set_* verdadeira)',
      () async {
        // Distinguir `null` de `[]` é o ponto do contrato: um remove permissões, o
        // outro não mexe nelas.
        when(
          () => client.updateTenantUser(any()),
        ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantUserResponse()));

        await _usecases(client).update(
          const UpdateTenantUserParameters(
            userId: 10,
            modulePermissions: [],
            flowPermissions: [],
          ),
        );

        final enviado =
            verify(() => client.updateTenantUser(captureAny())).captured.single
                as proto.UpdateTenantUserRequest;
        expect(enviado.setModulePermissions, isTrue);
        expect(enviado.modulePermissions, isEmpty);
        expect(enviado.setFlowPermissions, isTrue);
        expect(enviado.flowPermissions, isEmpty);
        expect(enviado.setRole, isFalse);
      },
    );

    test('usuário inexistente vira não encontrado', () async {
      when(
        () => client.updateTenantUser(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.notFound('sem usuario')));

      final r = await _usecases(
        client,
      ).update(const UpdateTenantUserParameters(userId: 999, role: 'gestor'));

      expect((r as Failure).error, isA<UsuarioNaoEncontrado>());
    });

    test('papel/permissão inválidos viram dados inválidos', () async {
      when(() => client.updateTenantUser(any())).thenAnswer(
        (_) =>
            falhaGrpc(proto.GrpcError.invalidArgument('fluxo de outro tenant')),
      );

      final r = await _usecases(client).update(
        const UpdateTenantUserParameters(userId: 10, flowPermissions: [99]),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<UsuariosDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
    });
  });

  group('TenantUsersController', () {
    blocTest<TenantUsersController, ViewState<List<TenantUser>>>(
      'carrega a lista: [Loading, Success]',
      build: () {
        listaResponde([usuarioItemProto()]);
        return _controller(client);
      },
      act: (c) => c.fetchUsers(),
      expect: () => [
        isA<LoadingState<List<TenantUser>>>(),
        isA<SuccessState<List<TenantUser>>>().having(
          (s) => s.data,
          'usuarios',
          hasLength(1),
        ),
      ],
    );

    blocTest<TenantUsersController, ViewState<List<TenantUser>>>(
      'falha: [Loading, Error]',
      build: () {
        when(
          () => client.listTenantUsers(any()),
        ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('offline')));
        return _controller(client);
      },
      act: (c) => c.fetchUsers(),
      expect: () => [
        isA<LoadingState<List<TenantUser>>>(),
        isA<ErrorState<List<TenantUser>>>().having(
          (s) => s.error,
          'erro',
          isA<UsuariosIndisponivel>(),
        ),
      ],
    );

    test('atualização bem-sucedida recarrega a lista', () async {
      listaResponde([usuarioItemProto()]);
      when(
        () => client.updateTenantUser(any()),
      ).thenAnswer((_) => respostaGrpc(proto.UpdateTenantUserResponse()));
      final controller = _controller(client);

      final r = await controller.updateUser(userId: 10, role: 'gestor');

      expect(r, isA<Success>());
      verify(() => client.listTenantUsers(any())).called(1);
      await controller.close();
    });

    test('atualização com falha não recarrega a lista', () async {
      listaResponde([usuarioItemProto()]);
      when(
        () => client.updateTenantUser(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.permissionDenied('x')));
      final controller = _controller(client);

      final r = await controller.updateUser(userId: 10, role: 'gestor');

      expect((r as Failure).error, isA<UsuariosAcessoNegado>());
      verifyNever(() => client.listTenantUsers(any()));
      await controller.close();
    });
  });
}
