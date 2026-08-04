import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/equipe_errors.dart';
import '../../domain/model/equipe.dart';
import '../../domain/parameters/equipe_parameters.dart';

EquipeError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.equipe',
    error: exception,
  );
  return switch (kind) {
    // O servidor recusa a criação com RESOURCE_EXHAUSTED quando o PLANO não
    // tem mais vagas. Traduzir para "indisponível" mandaria o tenant tentar de
    // novo para sempre; o caminho é mudar de plano.
    GrpcFailureKind.rateLimited => const LimiteDeDepartamentos(),
    GrpcFailureKind.notFound => const DepartamentoNaoEncontrado(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition => EquipeDadosInvalidos(
        exception is GrpcError ? exception.message : null,
      ),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const EquipeAcessoNegado(),
    GrpcFailureKind.unavailable => const EquipeIndisponivel(),
    GrpcFailureKind.unknown => const EquipeInesperado(),
  };
}

final class CarregarEquipeRepository
    extends RepositoryBase<Equipe, NoParams, EquipeError> {
  const CarregarEquipeRepository({required super.datasource});

  @override
  EquipeError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'carregar equipe');
}

final class CriarDepartamentoRepository
    extends RepositoryBase<Unit, CriarDepartamentoParameters, EquipeError> {
  const CriarDepartamentoRepository({required super.datasource});

  @override
  EquipeError mapError(Object e, StackTrace s, CriarDepartamentoParameters p) =>
      _traduzir(e, 'criar departamento');
}

final class AtualizarDepartamentoRepository
    extends RepositoryBase<Unit, AtualizarDepartamentoParameters, EquipeError> {
  const AtualizarDepartamentoRepository({required super.datasource});

  @override
  EquipeError mapError(
    Object e,
    StackTrace s,
    AtualizarDepartamentoParameters p,
  ) =>
      _traduzir(e, 'atualizar departamento');
}

final class DesativarDepartamentoRepository
    extends RepositoryBase<Unit, DepartamentoIdParameters, EquipeError> {
  const DesativarDepartamentoRepository({required super.datasource});

  @override
  EquipeError mapError(Object e, StackTrace s, DepartamentoIdParameters p) =>
      _traduzir(e, 'desativar departamento');
}

final class CriarAtendenteRepository
    extends RepositoryBase<Unit, CriarAtendenteParameters, EquipeError> {
  const CriarAtendenteRepository({required super.datasource});

  @override
  EquipeError mapError(Object e, StackTrace s, CriarAtendenteParameters p) =>
      _traduzir(e, 'criar atendente');
}

final class AtualizarAtendenteRepository
    extends RepositoryBase<Unit, AtualizarAtendenteParameters, EquipeError> {
  const AtualizarAtendenteRepository({required super.datasource});

  @override
  EquipeError mapError(Object e, StackTrace s, AtualizarAtendenteParameters p) =>
      _traduzir(e, 'atualizar atendente');
}

final class DesativarAtendenteRepository
    extends RepositoryBase<Unit, AtendenteIdParameters, EquipeError> {
  const DesativarAtendenteRepository({required super.datasource});

  @override
  EquipeError mapError(Object e, StackTrace s, AtendenteIdParameters p) =>
      _traduzir(e, 'desativar atendente');
}
