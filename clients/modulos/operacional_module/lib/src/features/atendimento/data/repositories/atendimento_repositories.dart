import 'dart:developer' as developer;

// `show` explícito: o api_client exporta tipos proto com os mesmos nomes dos
// modelos de domínio (AtendimentoResumo, MensagemThread).
import 'package:api_client/api_client.dart'
    show GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/parameters/get_thread_parameters.dart';
import '../../domain/parameters/list_atendimentos_parameters.dart';
import '../../domain/parameters/move_atendimento_etapa_parameters.dart';
import '../../domain/parameters/send_outbound_message_parameters.dart';

/// As quatro fronteiras da feature. Cada `mapError` traduz a natureza da falha
/// (transporte gRPC no Web, [LocalEngineFalha] no desktop) para o conjunto
/// fechado da sua operação.
///
/// O log registra a natureza e o id do atendimento — **nunca** o conteúdo da
/// mensagem, que é PII.

/// Classifica a exceção considerando os dois transportes possíveis.
///
/// Uma [LocalEngineFalha] não é falha de rede: o desktop lê do índice SQLite
/// local, e confundir as duas mandaria o usuário "tentar novamente" quando o que
/// resolve é reiniciar o aplicativo.
GrpcFailureKind? _kindDeTransporte(Object exception) =>
    exception is LocalEngineFalha ? null : classificarFalhaGrpc(exception);

void _log(
  String operacao,
  Object exception,
  StackTrace stackTrace, {
  int? atendimentoId,
}) {
  developer.log(
    '$operacao falhou${atendimentoId != null ? ' (atendimento $atendimentoId)' : ''}',
    name: 'operacional_module.atendimento',
    error: exception,
    stackTrace: stackTrace,
  );
}

final class ListAtendimentosRepository
    extends
        RepositoryBase<
          List<AtendimentoResumo>,
          ListAtendimentosParameters,
          ListAtendimentosError
        > {
  const ListAtendimentosRepository({required super.datasource});

  @override
  ListAtendimentosError mapError(
    Object exception,
    StackTrace stackTrace,
    ListAtendimentosParameters parameters,
  ) {
    _log('listAtendimentos', exception, stackTrace);
    return switch (_kindDeTransporte(exception)) {
      null => const ListAtendimentosFalhaLocal(),
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const ListAtendimentosAcessoNegado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const ListAtendimentosIndisponivel(),
      _ => const ListAtendimentosInesperado(),
    };
  }
}

final class GetThreadRepository
    extends
        RepositoryBase<
          List<MensagemThread>,
          GetThreadParameters,
          GetThreadError
        > {
  const GetThreadRepository({required super.datasource});

  @override
  GetThreadError mapError(
    Object exception,
    StackTrace stackTrace,
    GetThreadParameters parameters,
  ) {
    _log(
      'getThread',
      exception,
      stackTrace,
      atendimentoId: parameters.atendimentoId,
    );
    return switch (_kindDeTransporte(exception)) {
      null => const GetThreadFalhaLocal(),
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const GetThreadAcessoNegado(),
      GrpcFailureKind.notFound => const GetThreadNaoEncontrado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const GetThreadIndisponivel(),
      _ => const GetThreadInesperado(),
    };
  }
}

final class MoveAtendimentoEtapaRepository
    extends
        RepositoryBase<
          Unit,
          MoveAtendimentoEtapaParameters,
          MoveAtendimentoEtapaError
        > {
  const MoveAtendimentoEtapaRepository({required super.datasource});

  @override
  MoveAtendimentoEtapaError mapError(
    Object exception,
    StackTrace stackTrace,
    MoveAtendimentoEtapaParameters parameters,
  ) {
    _log(
      'moveAtendimentoEtapa',
      exception,
      stackTrace,
      atendimentoId: parameters.atendimentoId,
    );
    return switch (_kindDeTransporte(exception)) {
      null => const MoveEtapaFalhaLocal(),
      // O RBAC fino por fluxo é resolvido no servidor; aqui só se exibe.
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const MoveEtapaAcessoNegado(),
      GrpcFailureKind.notFound => const MoveEtapaNaoEncontrado(),
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => const MoveEtapaMovimentoInvalido(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const MoveEtapaIndisponivel(),
      _ => const MoveEtapaInesperado(),
    };
  }
}

final class SendOutboundMessageRepository
    extends
        RepositoryBase<
          int,
          SendOutboundMessageParameters,
          SendOutboundMessageError
        > {
  const SendOutboundMessageRepository({required super.datasource});

  @override
  SendOutboundMessageError mapError(
    Object exception,
    StackTrace stackTrace,
    SendOutboundMessageParameters parameters,
  ) {
    // Só o id vai para o log: `parameters.conteudo` é a mensagem do cliente.
    _log(
      'sendOutboundMessage',
      exception,
      stackTrace,
      atendimentoId: parameters.atendimentoId,
    );
    return switch (_kindDeTransporte(exception)) {
      null => const SendMessageFalhaLocal(),
      GrpcFailureKind.unauthenticated ||
      GrpcFailureKind.permissionDenied => const SendMessageAcessoNegado(),
      GrpcFailureKind.notFound => const SendMessageNaoEncontrado(),
      GrpcFailureKind.invalidArgument => const SendMessageConteudoInvalido(),
      GrpcFailureKind.failedPrecondition => const SendMessageEstadoInvalido(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const SendMessageIndisponivel(),
      _ => const SendMessageInesperado(),
    };
  }
}
