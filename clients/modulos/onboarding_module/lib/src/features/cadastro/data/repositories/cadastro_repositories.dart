import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/cadastro_errors.dart';
import '../../domain/model/cadastro_models.dart';
import '../../domain/parameters/cadastro_parameters.dart';

/// Fronteira do wizard: traduz a falha técnica no erro fechado da feature.
///
/// A tradução é a mesma para as sete operações (mesmo repertório de falha), então
/// mora num único lugar — [_traduzir]. O que muda entre elas é só o que se
/// registra no log.
///
/// **`invalidArgument` preserva a mensagem do servidor.** É a única exceção à
/// regra de não mostrar texto do servidor: essas mensagens são escritas para o
/// usuário final ("Este endereço já está em uso"), e o servidor é a autoridade
/// sobre a validação — a tela não tem como reproduzi-las. Os demais casos usam
/// texto fixo do cliente.
CadastroError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'onboarding_module.cadastro',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.invalidArgument => CadastroDadosInvalidos(
        exception is GrpcError ? exception.message : null,
      ),
    GrpcFailureKind.alreadyExists => const CadastroDadosInvalidos(),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied ||
    GrpcFailureKind.notFound => const CadastroNaoAutorizado(),
    GrpcFailureKind.failedPrecondition => const CadastroForaDeOrdem(),
    GrpcFailureKind.rateLimited => const CadastroBloqueadoPorTentativas(),
    GrpcFailureKind.unavailable => const CadastroIndisponivel(),
    GrpcFailureKind.unknown => const CadastroInesperado(),
  };
}

final class VerificarSlugRepository extends RepositoryBase<SlugDisponibilidade,
    SlugParameters, CadastroError> {
  const VerificarSlugRepository({required super.datasource});

  @override
  CadastroError mapError(Object e, StackTrace s, SlugParameters p) =>
      _traduzir(e, 'verificar slug');
}

final class ListarPlanosRepository extends RepositoryBase<List<PlanoPublico>,
    SemParametros, CadastroError> {
  const ListarPlanosRepository({required super.datasource});

  @override
  CadastroError mapError(Object e, StackTrace s, SemParametros p) =>
      _traduzir(e, 'listar planos');
}

final class ListarProvedoresRepository extends RepositoryBase<
    List<ProvedorPagamento>, SemParametros, CadastroError> {
  const ListarProvedoresRepository({required super.datasource});

  @override
  CadastroError mapError(Object e, StackTrace s, SemParametros p) =>
      _traduzir(e, 'listar provedores');
}

/// O log registra a **natureza** da falha, nunca os `parameters` — que aqui
/// carregam a senha.
final class IniciarCadastroRepository extends RepositoryBase<CadastroIniciado,
    IniciarCadastroParameters, CadastroError> {
  const IniciarCadastroRepository({required super.datasource});

  @override
  CadastroError mapError(Object e, StackTrace s, IniciarCadastroParameters p) =>
      _traduzir(e, 'iniciar cadastro');
}

final class SelecionarPlanoRepository
    extends RepositoryBase<int, SelecionarPlanoParameters, CadastroError> {
  const SelecionarPlanoRepository({required super.datasource});

  @override
  CadastroError mapError(Object e, StackTrace s, SelecionarPlanoParameters p) =>
      _traduzir(e, 'selecionar plano');
}

/// Idem: os `parameters` carregam o código de ativação.
final class ConfirmarPagamentoRepository extends RepositoryBase<
    ResultadoPagamento, ConfirmarPagamentoParameters, CadastroError> {
  const ConfirmarPagamentoRepository({required super.datasource});

  @override
  CadastroError mapError(
    Object e,
    StackTrace s,
    ConfirmarPagamentoParameters p,
  ) =>
      _traduzir(e, 'confirmar pagamento');
}

final class StatusCadastroRepository extends RepositoryBase<StatusCadastro,
    StatusCadastroParameters, CadastroError> {
  const StatusCadastroRepository({required super.datasource});

  @override
  CadastroError mapError(Object e, StackTrace s, StatusCadastroParameters p) =>
      _traduzir(e, 'consultar status');
}
