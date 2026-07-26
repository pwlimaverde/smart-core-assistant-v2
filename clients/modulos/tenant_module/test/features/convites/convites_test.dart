import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';
import 'package:tenant_module/src/features/convites/data/datasources/convites_datasources.dart';
import 'package:tenant_module/src/features/convites/data/repositories/convites_repositories.dart';
import 'package:tenant_module/src/features/convites/domain/errors/convites_errors.dart';
import 'package:tenant_module/src/features/convites/domain/model/accepted_tenant_user.dart';
import 'package:tenant_module/src/features/convites/domain/model/tenant_invite.dart';
import 'package:tenant_module/src/features/convites/domain/parameters/convites_parameters.dart';
import 'package:tenant_module/src/features/convites/domain/usecases/convites_usecases.dart';
import 'package:tenant_module/src/features/convites/presentation/controllers/accept_invite_controller.dart';
import 'package:tenant_module/src/features/convites/presentation/controllers/invites_controller.dart';

import '../../support/admin_client_mock.dart';

/// Monta a cadeia real de cada operação sobre o stub mockado.
({
  CreateInviteUsecase create,
  ListInvitesUsecase list,
  RevokeInviteUsecase revoke,
  AcceptInviteUsecase accept,
})
_usecases(MockAdminClient client) => (
  create: CreateInviteUsecase(
    repository: CreateInviteRepository(
      datasource: CreateInviteDatasource(client: client),
    ),
  ),
  list: ListInvitesUsecase(
    repository: ListInvitesRepository(
      datasource: ListInvitesDatasource(client: client),
    ),
  ),
  revoke: RevokeInviteUsecase(
    repository: RevokeInviteRepository(
      datasource: RevokeInviteDatasource(client: client),
    ),
  ),
  accept: AcceptInviteUsecase(
    repository: AcceptInviteRepository(
      datasource: AcceptInviteDatasource(client: client),
    ),
  ),
);

InvitesController _invitesController(MockAdminClient client) {
  final u = _usecases(client);
  return InvitesController(
    listUsecase: u.list,
    createUsecase: u.create,
    revokeUsecase: u.revoke,
  );
}

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoTenant);
  setUp(() => client = MockAdminClient());

  void listaResponde(List<proto.TenantInviteItem> itens) => when(
    () => client.listInvites(any()),
  ).thenAnswer((_) => respostaGrpc(proto.ListInvitesResponse(invites: itens)));

  group('ListInvites', () {
    test('converte os itens do protobuf', () async {
      listaResponde([
        conviteItemProto(
          id: 'inv-9',
          email: 'a@b.com',
          modulePermissions: const ['atendimentos:read'],
          flowPermissions: const [3, 4],
        ),
      ]);

      final r = await _usecases(client).list(noParams);

      final convite =
          (r as Success<List<TenantInvite>, ConvitesError>).value.single;
      expect(convite.id, 'inv-9');
      expect(convite.email, 'a@b.com');
      expect(convite.modulePermissions, ['atendimentos:read']);
      expect(convite.flowPermissions, [3, 4]);
      expect(convite.createdAt, DateTime(2026, 1, 1));
    });

    test('ordena pendentes primeiro, mais recentes no topo', () async {
      // A tela existe para agir sobre o que está pendente: um convite revogado
      // antigo não pode ficar acima de um pendente de hoje.
      listaResponde([
        conviteItemProto(
          id: 'revogado-novo',
          revoked: true,
          createdAt: DateTime(2026, 3, 1),
        ),
        conviteItemProto(
          id: 'pendente-antigo',
          createdAt: DateTime(2026, 1, 1),
        ),
        conviteItemProto(id: 'pendente-novo', createdAt: DateTime(2026, 2, 1)),
        conviteItemProto(
          id: 'usado',
          used: true,
          createdAt: DateTime(2026, 2, 15),
        ),
      ]);

      final r = await _usecases(client).list(noParams);

      expect((r as Success).value.map((i) => i.id).toList(), [
        'pendente-novo',
        'pendente-antigo',
        'revogado-novo',
        'usado',
      ]);
    });

    test('sem escopo de admin vira acesso negado', () async {
      when(() => client.listInvites(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      final erro = ((await _usecases(client).list(noParams)) as Failure).error;

      expect(erro, isA<ConvitesAcessoNegado>());
      expect(erro, isA<UnauthorizedFailure>());
    });

    test('servidor fora do ar é falha de rede', () async {
      when(
        () => client.listInvites(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.unavailable('offline')));

      expect(
        ((await _usecases(client).list(noParams)) as Failure).error,
        isA<ConvitesIndisponivel>(),
      );
    });
  });

  group('CreateInvite', () {
    test('envia os campos e devolve o convite com token', () async {
      when(() => client.createInvite(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateInviteResponse(
            invite: conviteCriadoProto(token: 'tok-123'),
          ),
        ),
      );

      final r = await _usecases(client).create(
        const CreateInviteParameters(
          email: 'novo@exemplo.com',
          name: 'Novo',
          role: 'atendente',
          modulePermissions: ['atendimentos:read'],
          flowPermissions: [1],
        ),
      );

      final enviado =
          verify(() => client.createInvite(captureAny())).captured.single
              as proto.CreateInviteRequest;
      expect(enviado.email, 'novo@exemplo.com');
      expect(enviado.modulePermissions, ['atendimentos:read']);
      expect(enviado.flowPermissions, [1]);
      expect((r as Success).value.token, 'tok-123');
    });

    test(
      'e-mail já convidado tem erro próprio (não é "dados inválidos")',
      () async {
        when(() => client.createInvite(any())).thenAnswer(
          (_) => falhaGrpc(proto.GrpcError.alreadyExists('convite pendente')),
        );

        final r = await _usecases(client).create(
          const CreateInviteParameters(
            email: 'ja@existe.com',
            name: 'X',
            role: 'atendente',
          ),
        );

        expect((r as Failure).error, isA<EmailJaConvidado>());
      },
    );

    test('papel inválido vira dados inválidos', () async {
      when(() => client.createInvite(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.invalidArgument('role desconhecido')),
      );

      final r = await _usecases(client).create(
        const CreateInviteParameters(
          email: 'a@b.com',
          name: 'X',
          role: 'inexistente',
        ),
      );

      final erro = (r as Failure).error;
      expect(erro, isA<ConvitesDadosInvalidos>());
      expect(erro, isA<ValidationFailure>());
    });

    test('o e-mail convidado não aparece na mensagem de erro', () async {
      when(() => client.createInvite(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.internal('falha em convidado@x.com')),
      );

      final r = await _usecases(client).create(
        const CreateInviteParameters(
          email: 'convidado@x.com',
          name: 'X',
          role: 'atendente',
        ),
      );

      expect(
        ((r as Failure).error as ConvitesError).message,
        isNot(contains('convidado@x.com')),
      );
    });
  });

  group('RevokeInvite', () {
    test('envia o id e resolve em Unit', () async {
      when(
        () => client.revokeInvite(any()),
      ).thenAnswer((_) => respostaGrpc(proto.RevokeInviteResponse()));

      final r = await _usecases(
        client,
      ).revoke(const RevokeInviteParameters(inviteId: 'inv-7'));

      final enviado =
          verify(() => client.revokeInvite(captureAny())).captured.single
              as proto.RevokeInviteRequest;
      expect(enviado.inviteId, 'inv-7');
      expect(r, isA<Success<Unit, ConvitesError>>());
    });

    test('convite inexistente vira não encontrado', () async {
      when(
        () => client.revokeInvite(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.notFound('sem convite')));

      final r = await _usecases(
        client,
      ).revoke(const RevokeInviteParameters(inviteId: 'inv-x'));

      expect((r as Failure).error, isA<ConviteNaoEncontrado>());
    });
  });

  group('AcceptInvite (rota pública)', () {
    const params = AcceptInviteParameters(
      token: 'tok',
      username: 'usuario',
      email: 'a@b.com',
      password: 'senha-forte',
    );

    test('devolve o vínculo criado', () async {
      when(() => client.acceptInvite(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.AcceptInviteResponse(
            tenantUser: proto.AcceptedTenantUser(
              id: 5,
              userId: 50,
              tenantId: 'tenant-1',
              role: 'atendente',
              isActive: true,
              modulePermissions: const ['atendimentos:read'],
              flowPermissions: const [2],
            ),
          ),
        ),
      );

      final r = await _usecases(client).accept(params);

      final vinculo = (r as Success).value;
      expect(vinculo.userId, 50);
      expect(vinculo.tenantId, 'tenant-1');
      expect(vinculo.flowPermissions, [2]);
    });

    test('token expirado, revogado ou inexistente dão o MESMO erro', () async {
      // Distinguir diria a quem tem o link se aquele convite já foi válido.
      for (final falha in [
        proto.GrpcError.notFound('nao existe'),
        proto.GrpcError.failedPrecondition('expirado'),
        proto.GrpcError.permissionDenied('revogado'),
      ]) {
        final c = MockAdminClient();
        when(() => c.acceptInvite(any())).thenAnswer((_) => falhaGrpc(falha));

        expect(
          ((await _usecases(c).accept(params)) as Failure).error,
          isA<ConviteInvalidoOuExpirado>(),
        );
      }
    });

    test('conta já existente tem erro próprio', () async {
      when(() => client.acceptInvite(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.alreadyExists('email em uso')),
      );

      expect(
        ((await _usecases(client).accept(params)) as Failure).error,
        isA<UsuarioJaExiste>(),
      );
    });

    test('a senha escolhida nunca aparece na mensagem de erro', () async {
      when(() => client.acceptInvite(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.internal('erro com senha-forte')),
      );

      final erro =
          ((await _usecases(client).accept(params)) as Failure).error
              as AcceptInviteError;

      expect(erro.message, isNot(contains('senha-forte')));
    });
  });

  group('InvitesController', () {
    blocTest<InvitesController, ViewState<List<TenantInvite>>>(
      'carrega a lista: [Loading, Success]',
      build: () {
        when(() => client.listInvites(any())).thenAnswer(
          (_) => respostaGrpc(
            proto.ListInvitesResponse(invites: [conviteItemProto()]),
          ),
        );
        return _invitesController(client);
      },
      act: (c) => c.fetchInvites(),
      expect: () => [
        isA<LoadingState<List<TenantInvite>>>(),
        isA<SuccessState<List<TenantInvite>>>().having(
          (s) => s.data,
          'convites',
          hasLength(1),
        ),
      ],
    );

    blocTest<InvitesController, ViewState<List<TenantInvite>>>(
      'falha na lista: [Loading, Error] com o caso concreto',
      build: () {
        when(
          () => client.listInvites(any()),
        ).thenAnswer((_) => falhaGrpc(proto.GrpcError.permissionDenied('x')));
        return _invitesController(client);
      },
      act: (c) => c.fetchInvites(),
      expect: () => [
        isA<LoadingState<List<TenantInvite>>>(),
        isA<ErrorState<List<TenantInvite>>>().having(
          (s) => s.error,
          'erro',
          isA<ConvitesAcessoNegado>(),
        ),
      ],
    );

    test('criar convite com sucesso recarrega a lista', () async {
      listaResponde([conviteItemProto()]);
      when(() => client.createInvite(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.CreateInviteResponse(invite: conviteCriadoProto()),
        ),
      );
      final controller = _invitesController(client);

      final r = await controller.createInvite(
        email: 'novo@exemplo.com',
        name: 'Novo',
        role: 'atendente',
      );

      expect(r, isA<Success>());
      verify(() => client.listInvites(any())).called(1);
      await controller.close();
    });

    test('criar convite com falha NÃO recarrega a lista', () async {
      listaResponde([conviteItemProto()]);
      when(
        () => client.createInvite(any()),
      ).thenAnswer((_) => falhaGrpc(proto.GrpcError.alreadyExists('pendente')));
      final controller = _invitesController(client);

      final r = await controller.createInvite(
        email: 'ja@existe.com',
        name: 'X',
        role: 'atendente',
      );

      expect((r as Failure).error, isA<EmailJaConvidado>());
      verifyNever(() => client.listInvites(any()));
      await controller.close();
    });

    test('revogar com sucesso recarrega a lista', () async {
      listaResponde([conviteItemProto()]);
      when(
        () => client.revokeInvite(any()),
      ).thenAnswer((_) => respostaGrpc(proto.RevokeInviteResponse()));
      final controller = _invitesController(client);

      final r = await controller.revokeInvite('inv-1');

      expect(r, isA<Success>());
      verify(() => client.listInvites(any())).called(1);
      await controller.close();
    });
  });

  group('AcceptInviteController', () {
    blocTest<AcceptInviteController, ViewState<AcceptedTenantUser>>(
      'aceite bem-sucedido: [Loading, Success]',
      build: () {
        when(() => client.acceptInvite(any())).thenAnswer(
          (_) => respostaGrpc(
            proto.AcceptInviteResponse(
              tenantUser: proto.AcceptedTenantUser(
                id: 1,
                userId: 10,
                tenantId: 'tenant-1',
                role: 'atendente',
                isActive: true,
              ),
            ),
          ),
        );
        return AcceptInviteController(acceptUsecase: _usecases(client).accept);
      },
      act: (c) => c.accept(
        token: 'tok',
        username: 'u',
        email: 'a@b.com',
        password: 'p',
      ),
      expect: () => [
        isA<LoadingState<AcceptedTenantUser>>(),
        isA<SuccessState<AcceptedTenantUser>>(),
      ],
    );

    blocTest<AcceptInviteController, ViewState<AcceptedTenantUser>>(
      'convite inválido: [Loading, Error]',
      build: () {
        when(
          () => client.acceptInvite(any()),
        ).thenAnswer((_) => falhaGrpc(proto.GrpcError.notFound('x')));
        return AcceptInviteController(acceptUsecase: _usecases(client).accept);
      },
      act: (c) => c.accept(
        token: 'tok',
        username: 'u',
        email: 'a@b.com',
        password: 'p',
      ),
      expect: () => [
        isA<LoadingState<AcceptedTenantUser>>(),
        isA<ErrorState<AcceptedTenantUser>>().having(
          (s) => s.error,
          'erro',
          isA<ConviteInvalidoOuExpirado>(),
        ),
      ],
    );
  });
}
