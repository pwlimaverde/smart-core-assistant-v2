import 'package:api_client/api_client.dart' as proto;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/model/migracao_de_escopos.dart';
import '../../domain/model/usuario_global.dart';
import '../../domain/parameters/usuarios_parameters.dart';

/// Datasources da feature `usuarios` (D7): I/O gRPC e conversão protobuf →
/// domínio. Burros — sem `try/catch`, a exceção sobe crua para o `mapError`.

/// `0` no `last_login` significa "nunca entrou".
///
/// `proto3` não tem opcional em `int64` sem marcá-lo, e o servidor manda zero
/// no lugar de nulo. Converter zero para o epoch faria a tela exibir
/// "01/01/1970" — uma data que parece dado e não é.
DateTime? _instanteOuNulo(int millis) =>
    millis == 0 ? null : DateTime.fromMillisecondsSinceEpoch(millis);

UsuarioGlobal _doProto(proto.AdminUserItem u) => UsuarioGlobal(
  id: u.id,
  username: u.username,
  email: u.email,
  nome: u.nome,
  ativo: u.isActive,
  superusuario: u.isSuperuser,
  ultimoLogin: _instanteOuNulo(u.lastLogin.toInt()),
  cadastradoEm: DateTime.fromMillisecondsSinceEpoch(u.dateJoined.toInt()),
  tenantDono: u.tenantDono,
  tenantMembro: u.tenantMembro,
  papel: u.papel,
);

/// Lista usuários de todos os tenants.
final class ListarUsuariosDatasource
    implements Datasource<List<UsuarioGlobal>, ListarUsuariosParameters> {
  final proto.AdminServiceClient _client;

  const ListarUsuariosDatasource({required this._client});

  @override
  Future<List<UsuarioGlobal>> call(ListarUsuariosParameters parameters) async {
    final resp = await _client.adminListUsers(
      proto.AdminListUsersRequest(
        busca: parameters.busca,
        limite: parameters.limite,
        offset: parameters.offset,
      ),
    );
    return resp.usuarios.map(_doProto).toList();
  }
}

/// Bloqueia/desbloqueia o acesso de um usuário.
final class DefinirUsuarioAtivoDatasource
    implements Datasource<Unit, DefinirUsuarioAtivoParameters> {
  final proto.AdminServiceClient _client;

  const DefinirUsuarioAtivoDatasource({required this._client});

  @override
  Future<Unit> call(DefinirUsuarioAtivoParameters parameters) async {
    await _client.adminSetUserActive(
      proto.AdminSetUserActiveRequest(
        userId: parameters.userId,
        ativo: parameters.ativo,
      ),
    );
    return unit;
  }
}

/// P18 — torna explícitos os escopos que cada vínculo tem hoje pelo papel.
final class MigrarEscoposDatasource
    implements Datasource<ResultadoDaMigracao, MigrarEscoposParameters> {
  final proto.AdminServiceClient _client;

  const MigrarEscoposDatasource({required this._client});

  @override
  Future<ResultadoDaMigracao> call(MigrarEscoposParameters parameters) async {
    final resp = await _client.migrarEscoposImplicitos(
      proto.MigrarEscoposImplicitosRequest(dryRun: parameters.simular),
    );
    return ResultadoDaMigracao(
      contagens: resp.contagens
          .map(
            (c) => GrupoAMigrar(
              tenantId: c.tenantId,
              tenantNome: c.tenantNome,
              papel: c.papel,
              quantidade: c.quantidade,
            ),
          )
          .toList(),
      total: resp.total,
      migrados: resp.migrados,
      pulados: resp.pulados,
      simulacao: resp.dryRun,
    );
  }
}
