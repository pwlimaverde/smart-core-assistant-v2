import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/contatos_errors.dart';
import '../../domain/model/contato.dart';
import '../../domain/parameters/contatos_parameters.dart';

ContatosError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.contatos',
    error: exception,
  );
  final doServidor = exception is GrpcError ? exception.message : null;

  return switch (kind) {
    GrpcFailureKind.notFound => const ContatoNaoEncontrado(),
    // Telefone já cadastrado, ou troca de número barrada pelo histórico. A
    // mensagem é do servidor porque só ele sabe qual dos dois é — e a
    // diferença muda o que a pessoa faz em seguida.
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition => ContatoEmConflito(doServidor),
    GrpcFailureKind.invalidArgument => ContatoInvalido(doServidor),
    // Separados de propósito: sessão expirada não é falta de
    // permissão, e juntar as duas manda a pessoa caçar um acesso
    // que ela já tem.
    GrpcFailureKind.unauthenticated => const ContatosSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const ContatosAcessoNegado(),
    GrpcFailureKind.unknown => const ContatosInesperado(),
    _ => const ContatosIndisponivel(),
  };
}

final class ListarContatosRepository
    extends
        RepositoryBase<List<Contato>, ListarContatosParameters, ContatosError> {
  const ListarContatosRepository({required super.datasource});

  @override
  ContatosError mapError(Object e, StackTrace s, ListarContatosParameters p) =>
      _traduzir(e, 'listar contatos');
}

final class CriarContatoRepository
    extends RepositoryBase<Contato, CriarContatoParameters, ContatosError> {
  const CriarContatoRepository({required super.datasource});

  @override
  ContatosError mapError(Object e, StackTrace s, CriarContatoParameters p) =>
      _traduzir(e, 'criar contato');
}

final class AtualizarContatoRepository
    extends RepositoryBase<Unit, AtualizarContatoParameters, ContatosError> {
  const AtualizarContatoRepository({required super.datasource});

  @override
  ContatosError mapError(
    Object e,
    StackTrace s,
    AtualizarContatoParameters p,
  ) => _traduzir(e, 'atualizar contato');
}

final class DefinirContatoAtivoRepository
    extends RepositoryBase<Unit, DefinirContatoAtivoParameters, ContatosError> {
  const DefinirContatoAtivoRepository({required super.datasource});

  @override
  ContatosError mapError(
    Object e,
    StackTrace s,
    DefinirContatoAtivoParameters p,
  ) => _traduzir(e, 'definir contato ativo');
}
