import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcError, GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/usuarios_errors.dart';
import '../../domain/model/migracao_de_escopos.dart';
import '../../domain/model/usuario_global.dart';
import '../../domain/parameters/usuarios_parameters.dart';

/// Fronteiras da feature `usuarios` (D7).
///
/// O log registra a natureza da falha e a operação — **nunca o termo buscado**,
/// que é nome ou e-mail de gente.
UsuariosError _mapUsuarios(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'admin_module.usuarios',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    // Separados de propósito: sessão expirada não é falta de
    // permissão, e juntar as duas manda a pessoa caçar um acesso
    // que ela já tem.
    GrpcFailureKind.unauthenticated => const UsuariosSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const UsuariosAcessoNegado(),
    GrpcFailureKind.notFound => const UsuariosNaoEncontrado(),
    // A recusa a bloquear o próprio acesso chega por aqui, e a mensagem do
    // servidor diz exatamente qual é o problema — repeti-la é melhor que um
    // texto genérico que obriga a adivinhar.
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition ||
    GrpcFailureKind.alreadyExists => UsuariosDadosInvalidos(
      exception is GrpcError ? exception.message : null,
    ),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const UsuariosIndisponivel(),
    GrpcFailureKind.unknown => const UsuariosInesperado(),
  };
}

final class ListarUsuariosRepository
    extends
        RepositoryBase<
          List<UsuarioGlobal>,
          ListarUsuariosParameters,
          UsuariosError
        > {
  const ListarUsuariosRepository({required super.datasource});

  @override
  UsuariosError mapError(Object e, StackTrace s, ListarUsuariosParameters p) =>
      _mapUsuarios('listarUsuarios', e, s);
}

final class DefinirUsuarioAtivoRepository
    extends RepositoryBase<Unit, DefinirUsuarioAtivoParameters, UsuariosError> {
  const DefinirUsuarioAtivoRepository({required super.datasource});

  @override
  UsuariosError mapError(
    Object e,
    StackTrace s,
    DefinirUsuarioAtivoParameters p,
  ) => _mapUsuarios('definirUsuarioAtivo', e, s);
}

final class MigrarEscoposRepository
    extends
        RepositoryBase<
          ResultadoDaMigracao,
          MigrarEscoposParameters,
          UsuariosError
        > {
  const MigrarEscoposRepository({required super.datasource});

  @override
  UsuariosError mapError(Object e, StackTrace s, MigrarEscoposParameters p) =>
      _mapUsuarios('migrarEscopos', e, s);
}
