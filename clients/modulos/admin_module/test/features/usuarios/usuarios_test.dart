import 'package:admin_module/src/features/usuarios/data/datasources/usuarios_datasources.dart';
import 'package:admin_module/src/features/usuarios/data/repositories/usuarios_repositories.dart';
import 'package:admin_module/src/features/usuarios/domain/errors/usuarios_errors.dart';
import 'package:admin_module/src/features/usuarios/domain/model/usuario_global.dart';
import 'package:admin_module/src/features/usuarios/domain/parameters/usuarios_parameters.dart';
import 'package:admin_module/src/features/usuarios/domain/usecases/usuarios_usecases.dart';
import 'package:admin_module/src/features/usuarios/presentation/controllers/usuarios_controller.dart';
import 'package:api_client/api_client.dart' show GrpcError;
import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/admin_grpc_mock.dart';

proto.AdminUserItem _itemProto({
  int id = 1,
  String username = 'ana',
  String email = 'ana@x.com',
  String nome = 'Ana Souza',
  bool isActive = true,
  bool isSuperuser = false,
  int lastLogin = 0,
  String tenantDono = '',
  String tenantMembro = '',
  String papel = '',
}) => proto.AdminUserItem(
  id: id,
  username: username,
  email: email,
  nome: nome,
  isActive: isActive,
  isSuperuser: isSuperuser,
  lastLogin: Int64(lastLogin),
  dateJoined: ms(DateTime(2026, 1, 10)),
  tenantDono: tenantDono,
  tenantMembro: tenantMembro,
  papel: papel,
);

UsuariosController _controller(MockAdminClient client) => UsuariosController(
  listar: ListarUsuariosUsecase(
    repository: ListarUsuariosRepository(
      datasource: ListarUsuariosDatasource(client: client),
    ),
  ),
  definirAtivo: DefinirUsuarioAtivoUsecase(
    repository: DefinirUsuarioAtivoRepository(
      datasource: DefinirUsuarioAtivoDatasource(client: client),
    ),
  ),
);

void main() {
  late MockAdminClient client;

  setUpAll(registrarFallbacksDoAdmin);
  setUp(() => client = MockAdminClient());

  group('listagem global', () {
    test('bloqueados vêm primeiro, depois por nome', () async {
      // Quem abre esta tela quase sempre veio investigar um acesso que não
      // funciona; deixar os bloqueados no topo poupa a busca no caso comum.
      when(() => client.adminListUsers(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.AdminListUsersResponse(
            usuarios: [
              _itemProto(id: 1, nome: 'Ana Souza'),
              _itemProto(id: 2, nome: 'Zeca Lima', isActive: false),
              _itemProto(id: 3, nome: 'Bruno Reis'),
            ],
          ),
        ),
      );

      final r = await ListarUsuariosUsecase(
        repository: ListarUsuariosRepository(
          datasource: ListarUsuariosDatasource(client: client),
        ),
      )(const ListarUsuariosParameters());

      final lista = (r as Success<List<UsuarioGlobal>, UsuariosError>).value;
      expect(lista.map((u) => u.id), [2, 1, 3]);
    });

    test('last_login zero vira "nunca entrou", não a data do epoch', () async {
      // `proto3` manda zero no lugar de nulo; converter direto exibiria
      // 01/01/1970 — uma data que parece dado e não é.
      when(() => client.adminListUsers(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.AdminListUsersResponse(usuarios: [_itemProto(lastLogin: 0)]),
        ),
      );

      final r = await ListarUsuariosUsecase(
        repository: ListarUsuariosRepository(
          datasource: ListarUsuariosDatasource(client: client),
        ),
      )(const ListarUsuariosParameters());

      expect(
        (r as Success<List<UsuarioGlobal>, UsuariosError>)
            .value
            .single
            .ultimoLogin,
        isNull,
      );
    });

    test('vínculo prioriza dono sobre funcionário', () async {
      // É o vínculo mais forte: quem abre a tela quer saber de quem é a conta
      // antes de saber o cargo.
      final usuario = UsuarioGlobal(
        id: 1,
        username: 'ana',
        email: 'ana@x.com',
        nome: 'Ana',
        ativo: true,
        superusuario: false,
        ultimoLogin: null,
        cadastradoEm: DateTime(2026, 1, 1),
        tenantDono: 'Empresa X',
        tenantMembro: 'Empresa Y',
        papel: 'staff',
      );

      expect(usuario.vinculo, 'Empresa X');
    });

    test('sem nome cadastrado, exibe o username', () async {
      final usuario = UsuarioGlobal(
        id: 1,
        username: 'ana',
        email: 'ana@x.com',
        nome: '   ',
        ativo: true,
        superusuario: false,
        ultimoLogin: null,
        cadastradoEm: DateTime(2026, 1, 1),
        tenantDono: '',
        tenantMembro: '',
        papel: '',
      );

      expect(usuario.exibicao, 'ana');
    });
  });

  group('bloqueio de acesso', () {
    test('recusa do servidor chega com a mensagem dele', () async {
      // O servidor recusa bloquear o próprio acesso, e a razão exata é o que
      // torna a recusa acionável — um texto genérico obrigaria a adivinhar.
      when(() => client.adminSetUserActive(any())).thenAnswer(
        (_) => falhaGrpc(
          GrpcError.invalidArgument('não é possível bloquear o próprio acesso'),
        ),
      );

      final r = await DefinirUsuarioAtivoUsecase(
        repository: DefinirUsuarioAtivoRepository(
          datasource: DefinirUsuarioAtivoDatasource(client: client),
        ),
      )(const DefinirUsuarioAtivoParameters(userId: 1, ativo: false));

      final erro = (r as Failure).error;
      expect(erro, isA<UsuariosDadosInvalidos>());
      expect(erro.message, contains('próprio acesso'));
    });

    test('sem escopo de superusuário vira acesso negado', () async {
      when(
        () => client.adminSetUserActive(any()),
      ).thenAnswer((_) => falhaGrpc(GrpcError.permissionDenied('sem escopo')));

      final r = await DefinirUsuarioAtivoUsecase(
        repository: DefinirUsuarioAtivoRepository(
          datasource: DefinirUsuarioAtivoDatasource(client: client),
        ),
      )(const DefinirUsuarioAtivoParameters(userId: 1, ativo: false));

      expect((r as Failure).error, isA<UsuariosAcessoNegado>());
    });

    test('o controller recarrega do servidor depois de bloquear', () async {
      // Refletir o clique em memória deixaria a lista mentindo quando o
      // servidor recusa.
      var chamadas = 0;
      when(() => client.adminListUsers(any())).thenAnswer((_) {
        chamadas++;
        return respostaGrpc(
          proto.AdminListUsersResponse(
            usuarios: [_itemProto(isActive: chamadas == 1)],
          ),
        );
      });
      when(() => client.adminSetUserActive(any())).thenAnswer(
        (_) => respostaGrpc(proto.AdminSetUserActiveResponse(ativo: false)),
      );

      final controller = _controller(client);
      addTearDown(controller.close);

      await controller.carregar();
      final erro = await controller.definirAtivo(userId: 1, ativo: false);

      expect(erro, isNull);
      expect(chamadas, 2, reason: 'a lista veio do servidor de novo');
      final estado = controller.state as SuccessState<List<UsuarioGlobal>>;
      expect(estado.data.single.ativo, isFalse);
    });

    test('a busca corrente sobrevive à recarga', () async {
      // Bloquear alguém não pode limpar o filtro que levou até ele.
      when(() => client.adminListUsers(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.AdminListUsersResponse(usuarios: [_itemProto()]),
        ),
      );
      when(() => client.adminSetUserActive(any())).thenAnswer(
        (_) => respostaGrpc(proto.AdminSetUserActiveResponse(ativo: false)),
      );

      final controller = _controller(client);
      addTearDown(controller.close);

      await controller.carregar(busca: 'ana');
      await controller.definirAtivo(userId: 1, ativo: false);

      expect(controller.busca, 'ana');
    });
  });
}
