import 'dart:developer' as developer;

import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/integracoes_errors.dart';
import '../../domain/model/mcp_grant.dart';
import '../../domain/parameters/integracoes_parameters.dart';

/// Tradução compartilhada pelas duas operações.
///
/// O log não inclui `client_id` nem `client_name`: o primeiro é URL de terceiro e
/// o segundo é texto de terceiro. Para diagnosticar basta a natureza da falha.
IntegracoesError _mapIntegracoes(
  String operacao,
  Object exception,
  StackTrace stackTrace,
) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'tenant_module.integracoes',
    error: exception,
    stackTrace: stackTrace,
  );
  return switch (kind) {
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const IntegracoesSessaoInvalida(),
    // O backend devolve `Validation` quando o grant não existe, é de outra
    // pessoa ou já foi revogado — os três indistinguíveis de propósito, para não
    // confirmar a existência de consentimento alheio.
    GrpcFailureKind.notFound ||
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition => const ConexaoNaoEncontrada(),
    GrpcFailureKind.alreadyExists => const ConexaoNaoEncontrada(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const IntegracoesIndisponivel(),
    GrpcFailureKind.unknown => const IntegracoesInesperado(),
  };
}

final class ListMcpGrantsRepository
    extends RepositoryBase<List<McpGrant>, NoParams, IntegracoesError> {
  const ListMcpGrantsRepository({required super.datasource});

  @override
  IntegracoesError mapError(
    Object exception,
    StackTrace stackTrace,
    NoParams parameters,
  ) => _mapIntegracoes('listMcpGrants', exception, stackTrace);
}

final class RevokeMcpGrantRepository
    extends RepositoryBase<int, RevokeMcpGrantParameters, IntegracoesError> {
  const RevokeMcpGrantRepository({required super.datasource});

  @override
  IntegracoesError mapError(
    Object exception,
    StackTrace stackTrace,
    RevokeMcpGrantParameters parameters,
  ) => _mapIntegracoes('revokeMcpGrant', exception, stackTrace);
}
