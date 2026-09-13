import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcError, GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/clientes_errors.dart';
import '../../domain/model/cliente.dart';
import '../../domain/parameters/clientes_parameters.dart';

/// Sem o documento no log: a exceção pode carregar o payload.
ClientesError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log('$operacao falhou: $kind', name: 'tenant_module.clientes');
  final doServidor = exception is GrpcError ? exception.message : null;
  return switch (kind) {
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.notFound ||
    GrpcFailureKind.failedPrecondition ||
    GrpcFailureKind.alreadyExists => ClienteInvalido(doServidor),
    GrpcFailureKind.unauthenticated => const ClientesSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const ClientesAcessoNegado(),
    GrpcFailureKind.unknown => const ClientesInesperado(),
    _ => const ClientesIndisponivel(),
  };
}

final class ListarClientesRepository
    extends
        RepositoryBase<List<Cliente>, ListarClientesParameters, ClientesError> {
  const ListarClientesRepository({required super.datasource});

  @override
  ClientesError mapError(Object e, StackTrace s, ListarClientesParameters p) =>
      _traduzir(e, 'listar clientes');
}

final class SalvarClienteRepository
    extends RepositoryBase<int, SalvarClienteParameters, ClientesError> {
  const SalvarClienteRepository({required super.datasource});

  @override
  ClientesError mapError(Object e, StackTrace s, SalvarClienteParameters p) =>
      _traduzir(e, 'salvar cliente');
}

final class DefinirClienteAtivoRepository
    extends RepositoryBase<Unit, DefinirClienteAtivoParameters, ClientesError> {
  const DefinirClienteAtivoRepository({required super.datasource});

  @override
  ClientesError mapError(
    Object e,
    StackTrace s,
    DefinirClienteAtivoParameters p,
  ) => _traduzir(e, 'definir cliente ativo');
}

final class ListarContatosDoClienteRepository
    extends
        RepositoryBase<
          List<ContatoDoCliente>,
          ClienteIdParameters,
          ClientesError
        > {
  const ListarContatosDoClienteRepository({required super.datasource});

  @override
  ClientesError mapError(Object e, StackTrace s, ClienteIdParameters p) =>
      _traduzir(e, 'listar contatos do cliente');
}

final class VincularContatoRepository
    extends RepositoryBase<Unit, VincularContatoParameters, ClientesError> {
  const VincularContatoRepository({required super.datasource});

  @override
  ClientesError mapError(Object e, StackTrace s, VincularContatoParameters p) =>
      _traduzir(e, 'vincular contato');
}
