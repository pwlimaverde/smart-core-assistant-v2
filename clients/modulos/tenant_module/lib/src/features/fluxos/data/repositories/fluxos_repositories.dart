import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/fluxos_errors.dart';
import '../../domain/model/fluxo.dart';
import '../../domain/parameters/fluxos_parameters.dart';

FluxosError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.fluxos',
    error: exception,
  );
  return switch (kind) {
    // RESOURCE_EXHAUSTED aqui é o teto do PLANO, não excesso de chamadas.
    // Traduzir para "tente de novo" mandaria o tenant repetir para sempre.
    GrpcFailureKind.rateLimited => const LimiteDeFluxos(),
    GrpcFailureKind.notFound => const FluxoNaoEncontrado(),
    // As regras de negócio do servidor chegam por aqui com o motivo escrito:
    // etapa ocupada, última fila de entrada, fluxo com conversa aberta.
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition => FluxosRecusado(
        exception is GrpcError ? exception.message : null,
      ),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const FluxosAcessoNegado(),
    GrpcFailureKind.unavailable => const FluxosIndisponivel(),
    GrpcFailureKind.unknown => const FluxosInesperado(),
  };
}

final class ListarFluxosRepository
    extends RepositoryBase<List<Fluxo>, NoParams, FluxosError> {
  const ListarFluxosRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'listar fluxos');
}

final class CriarFluxoRepository
    extends RepositoryBase<Unit, CriarFluxoParameters, FluxosError> {
  const CriarFluxoRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, CriarFluxoParameters p) =>
      _traduzir(e, 'criar fluxo');
}

final class AtualizarFluxoRepository
    extends RepositoryBase<Unit, AtualizarFluxoParameters, FluxosError> {
  const AtualizarFluxoRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, AtualizarFluxoParameters p) =>
      _traduzir(e, 'atualizar fluxo');
}

final class DesativarFluxoRepository
    extends RepositoryBase<Unit, FluxoIdParameters, FluxosError> {
  const DesativarFluxoRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, FluxoIdParameters p) =>
      _traduzir(e, 'desativar fluxo');
}

final class ListarEtapasRepository
    extends RepositoryBase<List<EtapaFluxo>, FluxoIdParameters, FluxosError> {
  const ListarEtapasRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, FluxoIdParameters p) =>
      _traduzir(e, 'listar etapas');
}

final class CriarEtapaRepository
    extends RepositoryBase<Unit, CriarEtapaParameters, FluxosError> {
  const CriarEtapaRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, CriarEtapaParameters p) =>
      _traduzir(e, 'criar etapa');
}

final class AtualizarEtapaRepository
    extends RepositoryBase<Unit, AtualizarEtapaParameters, FluxosError> {
  const AtualizarEtapaRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, AtualizarEtapaParameters p) =>
      _traduzir(e, 'atualizar etapa');
}

final class DesativarEtapaRepository
    extends RepositoryBase<Unit, EtapaIdParameters, FluxosError> {
  const DesativarEtapaRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, EtapaIdParameters p) =>
      _traduzir(e, 'remover etapa');
}

final class MoverEtapaRepository
    extends RepositoryBase<bool, MoverEtapaParameters, FluxosError> {
  const MoverEtapaRepository({required super.datasource});

  @override
  FluxosError mapError(Object e, StackTrace s, MoverEtapaParameters p) =>
      _traduzir(e, 'mover etapa');
}
