import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/campos_errors.dart';
import '../../domain/model/campo_personalizado.dart';
import '../../domain/parameters/campos_parameters.dart';

CamposError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.campos',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.notFound => const CampoNaoEncontrado(),
    // Nome repetido no mesmo escopo: o slug sai do nome, e dois campos com o
    // mesmo slug seriam indistinguíveis para a IA, que grava PELO slug.
    GrpcFailureKind.alreadyExists => const CampoDuplicado(),
    // A mensagem é do servidor, que é quem sabe o que falta — nome vazio,
    // lista sem opção, escopo de fluxo sem quadro.
    GrpcFailureKind.invalidArgument || GrpcFailureKind.failedPrecondition =>
      CampoInvalido(exception is GrpcError ? exception.message : null),
    // Sessão morta não é falta de permissão. Juntar as duas manda a pessoa
    // caçar um acesso que ela já tem.
    GrpcFailureKind.unauthenticated => const CamposSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const CamposAcessoNegado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const CamposIndisponivel(),
    _ => const CamposInesperado(),
  };
}

final class ListarCamposRepository
    extends RepositoryBase<List<CampoPersonalizado>, NoParams, CamposError> {
  const ListarCamposRepository({required super.datasource});

  @override
  CamposError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'listar campos');
}

final class CriarCampoRepository
    extends
        RepositoryBase<CampoPersonalizado, CriarCampoParameters, CamposError> {
  const CriarCampoRepository({required super.datasource});

  @override
  CamposError mapError(Object e, StackTrace s, CriarCampoParameters p) =>
      _traduzir(e, 'criar campo');
}

final class AtualizarCampoRepository
    extends RepositoryBase<Unit, AtualizarCampoParameters, CamposError> {
  const AtualizarCampoRepository({required super.datasource});

  @override
  CamposError mapError(Object e, StackTrace s, AtualizarCampoParameters p) =>
      _traduzir(e, 'atualizar campo');
}

final class DesativarCampoRepository
    extends RepositoryBase<Unit, CampoIdParameters, CamposError> {
  const DesativarCampoRepository({required super.datasource});

  @override
  CamposError mapError(Object e, StackTrace s, CampoIdParameters p) =>
      _traduzir(e, 'desativar campo');
}
