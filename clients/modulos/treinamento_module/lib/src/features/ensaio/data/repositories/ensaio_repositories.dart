import 'dart:developer' as developer;

import 'package:api_client/api_client.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/ensaio_errors.dart';
import '../../domain/model/ensaio.dart';
import '../../domain/parameters/ensaio_parameters.dart';

final class TestarPerguntaRepository
    extends RepositoryBase<Ensaio, TestarPerguntaParameters, EnsaioError> {
  const TestarPerguntaRepository({required super.datasource});

  @override
  EnsaioError mapError(Object e, StackTrace s, TestarPerguntaParameters p) {
    final kind = classificarFalhaGrpc(e);
    developer.log(
      'testar pergunta falhou: $kind',
      name: 'treinamento_module.ensaio',
      error: e,
    );
    return switch (kind) {
      // Separados de propósito: sessão expirada não é falta de
      // permissão, e juntar as duas manda a pessoa caçar um acesso
      // que ela já tem.
      GrpcFailureKind.unauthenticated => const EnsaioSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const EnsaioAcessoNegado(),
      GrpcFailureKind.invalidArgument => EnsaioPerguntaInvalida(
        e is GrpcError ? e.message : null,
      ),
      // O servidor devolve `unavailable` quando o provedor de IA não respondeu:
      // esperar é a ação certa, não mexer no treinamento.
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const EnsaioIaIndisponivel(),
      _ => const EnsaioInesperado(),
    };
  }
}

/// B9 (N10 E6) — mesma tradução de falhas do ensaio; o que muda é o texto do
/// servidor para avaliação recusada.
final class RegistrarFeedbackTesteRepository
    extends RepositoryBase<int, RegistrarFeedbackTesteParameters, EnsaioError> {
  const RegistrarFeedbackTesteRepository({required super.datasource});

  @override
  EnsaioError mapError(
    Object e,
    StackTrace s,
    RegistrarFeedbackTesteParameters p,
  ) {
    final kind = classificarFalhaGrpc(e);
    developer.log(
      'registrar avaliação do teste falhou: $kind',
      name: 'treinamento_module.ensaio',
      error: e,
    );
    return switch (kind) {
      GrpcFailureKind.unauthenticated => const EnsaioSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const EnsaioAcessoNegado(),
      GrpcFailureKind.invalidArgument => EnsaioPerguntaInvalida(
        e is GrpcError ? e.message : null,
      ),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const EnsaioIaIndisponivel(),
      _ => const EnsaioInesperado(),
    };
  }
}
