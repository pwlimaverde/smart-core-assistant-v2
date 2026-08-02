import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/configuracao_errors.dart';
import '../../domain/model/configuracao_models.dart';
import '../../domain/parameters/configuracao_parameters.dart';

/// Fronteira da configuração guiada.
///
/// O caso que merece atenção é `rateLimited`: o `data_whatsapp` recusa a criação
/// de instância com RESOURCE_EXHAUSTED quando o **plano** do tenant não tem mais
/// vagas (`max_instances`). Traduzir isso para "servidor indisponível" mandaria
/// o cliente tentar de novo para sempre — é [LimiteDoPlanoAtingido], e a tela
/// precisa dizer que o caminho é mudar de plano.
ConfiguracaoError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'onboarding_module.configuracao',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.rateLimited => const LimiteDoPlanoAtingido(),
    GrpcFailureKind.invalidArgument => ConfiguracaoDadosInvalidos(
        exception is GrpcError ? exception.message : null,
      ),
    GrpcFailureKind.alreadyExists => const ConfiguracaoDadosInvalidos(
        'Já existe uma conexão com esse nome. Escolha outro.',
      ),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const ConfiguracaoNaoAutorizada(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.notFound ||
    GrpcFailureKind.failedPrecondition => const ConfiguracaoIndisponivel(),
    GrpcFailureKind.unknown => const ConfiguracaoInesperada(),
  };
}

final class CriarConexaoRepository extends RepositoryBase<ConexaoWhatsapp,
    CriarConexaoParameters, ConfiguracaoError> {
  const CriarConexaoRepository({required super.datasource});

  @override
  ConfiguracaoError mapError(Object e, StackTrace s, CriarConexaoParameters p) =>
      _traduzir(e, 'criar conexão');
}

final class EstadoConexaoRepository extends RepositoryBase<EstadoConexao,
    EstadoConexaoParameters, ConfiguracaoError> {
  const EstadoConexaoRepository({required super.datasource});

  @override
  ConfiguracaoError mapError(
    Object e,
    StackTrace s,
    EstadoConexaoParameters p,
  ) =>
      _traduzir(e, 'consultar conexão');
}

final class CriarDepartamentoRepository extends RepositoryBase<Departamento,
    CriarDepartamentoParameters, ConfiguracaoError> {
  const CriarDepartamentoRepository({required super.datasource});

  @override
  ConfiguracaoError mapError(
    Object e,
    StackTrace s,
    CriarDepartamentoParameters p,
  ) =>
      _traduzir(e, 'criar departamento');
}

final class DefinirPersonaRepository
    extends RepositoryBase<Unit, PersonaParameters, ConfiguracaoError> {
  const DefinirPersonaRepository({required super.datasource});

  @override
  ConfiguracaoError mapError(Object e, StackTrace s, PersonaParameters p) =>
      _traduzir(e, 'definir persona');
}

final class ProgressoRepository extends RepositoryBase<ProgressoOnboarding,
    ProgressoParameters, ConfiguracaoError> {
  const ProgressoRepository({required super.datasource});

  @override
  ConfiguracaoError mapError(Object e, StackTrace s, ProgressoParameters p) =>
      _traduzir(e, 'registrar progresso');
}

final class ConsultarProgressoRepository
    extends RepositoryBase<ProgressoOnboarding, NoParams, ConfiguracaoError> {
  const ConsultarProgressoRepository({required super.datasource});

  @override
  ConfiguracaoError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'consultar progresso');
}
