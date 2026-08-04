import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/contatos_errors.dart';
import '../../domain/model/contato.dart';
import '../../domain/parameters/contatos_parameters.dart';

final class ListarContatosRepository extends RepositoryBase<List<Contato>,
    ListarContatosParameters, ContatosError> {
  const ListarContatosRepository({required super.datasource});

  @override
  ContatosError mapError(Object e, StackTrace s, ListarContatosParameters p) {
    final kind = classificarFalhaGrpc(e);
    developer.log(
      'listar contatos falhou: $kind',
      name: 'tenant_module.contatos',
      error: e,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const ContatosAcessoNegado(),
      GrpcFailureKind.unknown => const ContatosInesperado(),
      _ => const ContatosIndisponivel(),
    };
  }
}
