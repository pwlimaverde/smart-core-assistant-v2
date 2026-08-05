import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/intents_errors.dart';
import '../../domain/model/intent.dart';
import '../../domain/parameters/intents_parameters.dart';

IntentsError _traduzir(Object exception, String operacao) {
  final kind = classificarFalhaGrpc(exception);
  developer.log(
    '$operacao falhou: $kind',
    name: 'treinamento_module.intents',
    error: exception,
  );
  return switch (kind) {
    GrpcFailureKind.notFound => const IntentNaoEncontrada(),
    // `alreadyExists` é a UNIQUE (tenant, tag, grupo): a mensagem do servidor
    // diz qual dupla colidiu, e reescrevê-la aqui perderia isso.
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition => IntentsRecusado(
        exception is GrpcError ? exception.message : null,
      ),
    GrpcFailureKind.unauthenticated ||
    GrpcFailureKind.permissionDenied => const IntentsAcessoNegado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const IntentsIndisponivel(),
    GrpcFailureKind.unknown => const IntentsInesperado(),
  };
}

final class ListarIntentsRepository
    extends RepositoryBase<List<IntentIa>, NoParams, IntentsError> {
  const ListarIntentsRepository({required super.datasource});

  @override
  IntentsError mapError(Object e, StackTrace s, NoParams p) =>
      _traduzir(e, 'listar intenções');
}

final class CriarIntentRepository
    extends RepositoryBase<Unit, CriarIntentParameters, IntentsError> {
  const CriarIntentRepository({required super.datasource});

  @override
  IntentsError mapError(Object e, StackTrace s, CriarIntentParameters p) =>
      _traduzir(e, 'criar intenção');
}

final class AtualizarIntentRepository
    extends RepositoryBase<Unit, AtualizarIntentParameters, IntentsError> {
  const AtualizarIntentRepository({required super.datasource});

  @override
  IntentsError mapError(Object e, StackTrace s, AtualizarIntentParameters p) =>
      _traduzir(e, 'atualizar intenção');
}

final class RemoverIntentRepository
    extends RepositoryBase<Unit, IntentIdParameters, IntentsError> {
  const RemoverIntentRepository({required super.datasource});

  @override
  IntentsError mapError(Object e, StackTrace s, IntentIdParameters p) =>
      _traduzir(e, 'remover intenção');
}
