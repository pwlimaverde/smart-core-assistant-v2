// ignore_for_file: implementation_imports
import 'package:grpc/src/shared/status.dart';

/// Natureza de uma falha vinda da borda gRPC, **sem** semântica de domínio.
///
/// É o vocabulário intermediário entre o status code do transporte e o erro de
/// domínio de cada feature: a tabela de status codes existe **uma vez** (aqui),
/// e cada `RepositoryBase.mapError` decide o que aquela natureza significa na
/// sua feature — `alreadyExists` é "slug de tenant duplicado" no cadastro de
/// tenants e "convite já aceito" nos convites.
///
/// Antes desta migração, os quatro módulos carregavam cópias quase idênticas de
/// um `mapGrpcError(GrpcError, AppError fallback)` que já devolvia o erro final,
/// misturando as duas responsabilidades e obrigando cada cópia a conhecer os
/// erros globais.
enum GrpcFailureKind {
  /// Sem credencial, token inválido ou expirado (`unauthenticated`).
  unauthenticated,

  /// Autenticado, porém sem escopo/permissão — inclui o RBAC fino por fluxo,
  /// que é resolvido 100% no servidor (`permissionDenied`).
  permissionDenied,

  /// Entrada rejeitada pela validação do servidor (`invalidArgument`).
  invalidArgument,

  /// Entrada válida, estado incompatível: a operação não cabe agora
  /// (`failedPrecondition`).
  failedPrecondition,

  /// O recurso pedido não existe (`notFound`).
  notFound,

  /// Conflito com um recurso existente (`alreadyExists`).
  alreadyExists,

  /// Rate limit ou quota estourada (`resourceExhausted`).
  rateLimited,

  /// Servidor fora do ar, prazo esgotado ou conexão perdida
  /// (`unavailable`, `deadlineExceeded`, `cancelled`).
  unavailable,

  /// Qualquer outra coisa — inclui o que **não** é um [GrpcError] (uma
  /// `FormatException` do mapeamento, um bug no datasource). Sempre traduzido
  /// para o caso "inesperado" da feature.
  unknown,
}

/// Classifica a falha que chegou ao `mapError`.
///
/// Aceita `Object` de propósito: o que o `RepositoryBase` captura é *qualquer*
/// exceção do datasource, não só [GrpcError] — e o que não vem do transporte é
/// [GrpcFailureKind.unknown], nunca um palpite.
GrpcFailureKind classificarFalhaGrpc(Object exception) {
  if (exception is! GrpcError) return GrpcFailureKind.unknown;
  return switch (exception.code) {
    StatusCode.unauthenticated => GrpcFailureKind.unauthenticated,
    StatusCode.permissionDenied => GrpcFailureKind.permissionDenied,
    StatusCode.invalidArgument => GrpcFailureKind.invalidArgument,
    StatusCode.failedPrecondition => GrpcFailureKind.failedPrecondition,
    StatusCode.notFound => GrpcFailureKind.notFound,
    StatusCode.alreadyExists => GrpcFailureKind.alreadyExists,
    StatusCode.resourceExhausted => GrpcFailureKind.rateLimited,
    StatusCode.unavailable ||
    StatusCode.deadlineExceeded ||
    StatusCode.cancelled => GrpcFailureKind.unavailable,
    _ => GrpcFailureKind.unknown,
  };
}
