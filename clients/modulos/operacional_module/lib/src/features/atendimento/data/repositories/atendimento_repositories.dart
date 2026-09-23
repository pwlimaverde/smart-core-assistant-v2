import 'dart:developer' as developer;

// `show` explícito: o api_client exporta tipos proto com os mesmos nomes dos
// modelos de domínio (AtendimentoResumo, MensagemThread).
import 'package:api_client/api_client.dart'
    show GrpcError, GrpcFailureKind, classificarFalhaGrpc;
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/parameters/definir_valor_campo_parameters.dart';
import '../../domain/parameters/iniciar_atendimento_parameters.dart';
import '../../domain/model/atendimento_iniciado.dart';
import '../../domain/errors/atendimento_errors.dart';
import '../../domain/gateways/atendimento_gateway.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/mensagem_thread.dart';
import '../../domain/parameters/get_thread_parameters.dart';
import '../../domain/parameters/list_atendimentos_parameters.dart';
import '../../domain/parameters/move_atendimento_etapa_parameters.dart';
import '../../domain/model/ficha.dart';
import '../../domain/model/quadro.dart';
import '../../domain/parameters/ficha_parameters.dart';
import '../../domain/parameters/quadro_parameters.dart';
import '../../domain/parameters/send_outbound_message_parameters.dart';
import '../../domain/model/midia_mensagem.dart';
import '../../domain/parameters/presenca_parameters.dart';
import '../../domain/parameters/quadro_operacao_parameters.dart';
import '../../domain/model/evento_timeline.dart';
import '../../domain/model/contato_da_conversa.dart';

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
      // Separados de propósito: sessão expirada não é falta de
      // permissão, e juntar as duas manda a pessoa caçar um acesso
      // que ela já tem.
      GrpcFailureKind.unauthenticated => const ListAtendimentosSessaoExpirada(),
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
      // Separados de propósito: sessão expirada não é falta de
      // permissão, e juntar as duas manda a pessoa caçar um acesso
      // que ela já tem.
      GrpcFailureKind.unauthenticated => const GetThreadSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const GetThreadAcessoNegado(),
      GrpcFailureKind.notFound => const GetThreadNaoEncontrado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const GetThreadIndisponivel(),
      _ => const GetThreadInesperado(),
    };
  }
}

final class IniciarAtendimentoRepository
    extends
        RepositoryBase<
          AtendimentoIniciado,
          IniciarAtendimentoParameters,
          IniciarAtendimentoError
        > {
  const IniciarAtendimentoRepository({required super.datasource});

  @override
  IniciarAtendimentoError mapError(
    Object exception,
    StackTrace stackTrace,
    IniciarAtendimentoParameters parameters,
  ) {
    _log(
      'iniciarAtendimento',
      exception,
      stackTrace,
      atendimentoId: parameters.contatoId,
    );
    return switch (_kindDeTransporte(exception)) {
      null => const IniciarAtendimentoInesperado(),
      // Sessão expirada não é falta de permissão — ver a nota em
      // `MoveAtendimentoEtapaRepository`.
      GrpcFailureKind.unauthenticated =>
        const IniciarAtendimentoSessaoExpirada(),
      GrpcFailureKind.permissionDenied =>
        const IniciarAtendimentoAcessoNegado(),
      GrpcFailureKind.notFound => const IniciarAtendimentoNaoEncontrado(),
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => const IniciarAtendimentoInvalido(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const IniciarAtendimentoIndisponivel(),
      _ => const IniciarAtendimentoInesperado(),
    };
  }
}

final class DefinirValorCampoRepository
    extends
        RepositoryBase<
          Unit,
          DefinirValorCampoParameters,
          DefinirValorCampoError
        > {
  const DefinirValorCampoRepository({required super.datasource});

  @override
  DefinirValorCampoError mapError(
    Object exception,
    StackTrace stackTrace,
    DefinirValorCampoParameters parameters,
  ) {
    _log(
      'definirValorCampo',
      exception,
      stackTrace,
      atendimentoId: parameters.atendimentoId,
    );
    return switch (_kindDeTransporte(exception)) {
      null => const ValorCampoInesperado(),
      GrpcFailureKind.unauthenticated => const ValorCampoSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const ValorCampoAcessoNegado(),
      GrpcFailureKind.notFound => const ValorCampoNaoEncontrado(),
      GrpcFailureKind.invalidArgument || GrpcFailureKind.failedPrecondition =>
        ValorCampoInvalido(exception is GrpcError ? exception.message : null),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const ValorCampoIndisponivel(),
      _ => const ValorCampoInesperado(),
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
      // Separados de propósito: sessão expirada não é falta de
      // permissão, e juntar as duas manda a pessoa caçar um acesso
      // que ela já tem.
      GrpcFailureKind.unauthenticated => const MoveEtapaSessaoExpirada(),
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
      // Separados de propósito: sessão expirada não é falta de
      // permissão, e juntar as duas manda a pessoa caçar um acesso
      // que ela já tem.
      GrpcFailureKind.unauthenticated => const SendMessageSessaoExpirada(),
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

QuadroError _erroDeQuadro(Object exception, StackTrace stackTrace) {
  _log('quadro', exception, stackTrace);
  return switch (_kindDeTransporte(exception)) {
    null => const QuadroFalhaLocal(),
    // Separados de propósito: sessão expirada não é falta de
    // permissão, e juntar as duas manda a pessoa caçar um acesso
    // que ela já tem.
    GrpcFailureKind.unauthenticated => const QuadroSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const QuadroAcessoNegado(),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const QuadroIndisponivel(),
    _ => const QuadroInesperado(),
  };
}

final class ListFluxosRepository
    extends RepositoryBase<List<FluxoDoQuadro>, NoParams, QuadroError> {
  const ListFluxosRepository({required super.datasource});

  @override
  QuadroError mapError(Object e, StackTrace s, NoParams p) =>
      _erroDeQuadro(e, s);
}

final class ListColunasRepository
    extends
        RepositoryBase<
          List<ColunaDoQuadro>,
          ListColunasParameters,
          QuadroError
        > {
  const ListColunasRepository({required super.datasource});

  @override
  QuadroError mapError(Object e, StackTrace s, ListColunasParameters p) =>
      _erroDeQuadro(e, s);
}

final class SetAtendimentoStatusRepository
    extends
        RepositoryBase<Unit, SetAtendimentoStatusParameters, SetStatusError> {
  const SetAtendimentoStatusRepository({required super.datasource});

  @override
  SetStatusError mapError(
    Object exception,
    StackTrace stackTrace,
    SetAtendimentoStatusParameters parameters,
  ) {
    _log(
      'setAtendimentoStatus',
      exception,
      stackTrace,
      atendimentoId: parameters.atendimentoId,
    );
    return switch (_kindDeTransporte(exception)) {
      null => const SetStatusFalhaLocal(),
      // Separados de propósito: sessão expirada não é falta de
      // permissão, e juntar as duas manda a pessoa caçar um acesso
      // que ela já tem.
      GrpcFailureKind.unauthenticated => const SetStatusSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const SetStatusAcessoNegado(),
      GrpcFailureKind.notFound => const SetStatusNaoEncontrado(),
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => const SetStatusRecusado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const SetStatusIndisponivel(),
      _ => const SetStatusInesperado(),
    };
  }
}

FichaError _erroDeFicha(Object exception, StackTrace stackTrace, int? id) {
  _log('ficha', exception, stackTrace, atendimentoId: id);
  return switch (_kindDeTransporte(exception)) {
    null => const FichaFalhaLocal(),
    // Separados de propósito: sessão expirada não é falta de
    // permissão, e juntar as duas manda a pessoa caçar um acesso
    // que ela já tem.
    GrpcFailureKind.unauthenticated => const FichaSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const FichaAcessoNegado(),
    // `alreadyExists` é a UNIQUE (tenant, nome) da etiqueta: a mensagem do
    // servidor diz qual nome colidiu.
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.alreadyExists ||
    GrpcFailureKind.failedPrecondition => FichaRecusado(
      exception is GrpcError ? exception.message : null,
    ),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const FichaIndisponivel(),
    _ => const FichaInesperado(),
  };
}

final class GetFichaRepository
    extends
        RepositoryBase<FichaAtendimento, AtendimentoIdParameters, FichaError> {
  const GetFichaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, AtendimentoIdParameters p) =>
      _erroDeFicha(e, s, p.atendimentoId);
}

final class CriarEtiquetaRepository
    extends RepositoryBase<Unit, CriarEtiquetaParameters, FichaError> {
  const CriarEtiquetaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, CriarEtiquetaParameters p) =>
      _erroDeFicha(e, s, null);
}

final class AlternarEtiquetaRepository
    extends RepositoryBase<Unit, AlternarEtiquetaParameters, FichaError> {
  const AlternarEtiquetaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, AlternarEtiquetaParameters p) =>
      _erroDeFicha(e, s, p.atendimentoId);
}

final class DefinirBotDaConversaRepository
    extends RepositoryBase<Unit, DefinirBotDaConversaParameters, FichaError> {
  const DefinirBotDaConversaRepository({required super.datasource});

  @override
  FichaError mapError(
    Object e,
    StackTrace s,
    DefinirBotDaConversaParameters p,
  ) => _erroDeFicha(e, s, p.atendimentoId);
}

final class MarcarAtendimentoLidoRepository
    extends RepositoryBase<int, MarcarAtendimentoLidoParameters, FichaError> {
  const MarcarAtendimentoLidoRepository({required super.datasource});

  @override
  FichaError mapError(
    Object e,
    StackTrace s,
    MarcarAtendimentoLidoParameters p,
  ) => _erroDeFicha(e, s, p.atendimentoId);
}

final class CriarNotaRepository
    extends RepositoryBase<Unit, CriarNotaParameters, FichaError> {
  const CriarNotaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, CriarNotaParameters p) =>
      _erroDeFicha(e, s, p.atendimentoId);
}

/// P3 — presença: qualquer falha vira "não entregue". Não há o que a pessoa
/// possa fazer com o detalhe, e a conversa continua normalmente.
final class EnviarPresencaRepository
    extends RepositoryBase<bool, EnviarPresencaParameters, PresencaError> {
  const EnviarPresencaRepository({required super.datasource});

  @override
  PresencaError mapError(Object e, StackTrace s, EnviarPresencaParameters p) {
    _log('enviarPresenca', e, s, atendimentoId: p.atendimentoId);
    return switch (_kindDeTransporte(e)) {
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const PresencaNaoEntregue(),
      _ => const PresencaInesperado(),
    };
  }
}

final class ListarMidiasRepository
    extends
        RepositoryBase<
          List<MidiaMensagem>,
          ListarMidiasParameters,
          MidiasError
        > {
  const ListarMidiasRepository({required super.datasource});

  @override
  MidiasError mapError(Object e, StackTrace s, ListarMidiasParameters p) {
    _log('listarMidias', e, s, atendimentoId: p.atendimentoId);
    return switch (_kindDeTransporte(e)) {
      null => const MidiasFalhaLocal(),
      GrpcFailureKind.unauthenticated => const MidiasSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const MidiasAcessoNegado(),
      GrpcFailureKind.unavailable ||
      GrpcFailureKind.rateLimited => const MidiasIndisponivel(),
      _ => const MidiasInesperado(),
    };
  }
}

final class EnviarMidiaRepository
    extends RepositoryBase<int, EnviarMidiaParameters, EnviarMidiaError> {
  const EnviarMidiaRepository({required super.datasource});

  @override
  EnviarMidiaError mapError(Object e, StackTrace s, EnviarMidiaParameters p) {
    // Nunca os bytes nem o nome do arquivo: os dois são do cliente.
    _log('enviarMidia', e, s, atendimentoId: p.atendimentoId);
    return switch (_kindDeTransporte(e)) {
      GrpcFailureKind.unauthenticated => const EnviarMidiaSessaoExpirada(),
      GrpcFailureKind.permissionDenied => const EnviarMidiaAcessoNegado(),
      GrpcFailureKind.invalidArgument ||
      GrpcFailureKind.failedPrecondition => EnviarMidiaRecusado(
        e is GrpcError ? e.message : null,
      ),
      // `rateLimited` é o `resourceExhausted` do gRPC, que aqui significa cota
      // de armazenamento estourada: é recusa, não instabilidade.
      GrpcFailureKind.rateLimited => EnviarMidiaRecusado(
        e is GrpcError ? e.message : null,
      ),
      GrpcFailureKind.unavailable => const EnviarMidiaIndisponivel(),
      _ => const EnviarMidiaInesperado(),
    };
  }
}

/// P4 — as quatro operações do quadro classificam a falha do mesmo jeito.
QuadroOperacaoError _erroDeOperacaoDoQuadro(
  Object e,
  StackTrace s,
  int? atendimentoId,
) {
  _log('quadroOperacao', e, s, atendimentoId: atendimentoId);
  return switch (_kindDeTransporte(e)) {
    GrpcFailureKind.unauthenticated => const QuadroOperacaoSessaoExpirada(),
    GrpcFailureKind.permissionDenied => const QuadroOperacaoAcessoNegado(),
    GrpcFailureKind.invalidArgument ||
    GrpcFailureKind.failedPrecondition ||
    GrpcFailureKind.notFound => QuadroOperacaoRecusada(
      e is GrpcError ? e.message : null,
    ),
    GrpcFailureKind.unavailable ||
    GrpcFailureKind.rateLimited => const QuadroOperacaoIndisponivel(),
    _ => const QuadroOperacaoInesperado(),
  };
}

final class AtribuirAtendimentoRepository
    extends
        RepositoryBase<
          bool,
          AtribuirAtendimentoParameters,
          QuadroOperacaoError
        > {
  const AtribuirAtendimentoRepository({required super.datasource});

  @override
  QuadroOperacaoError mapError(
    Object e,
    StackTrace s,
    AtribuirAtendimentoParameters p,
  ) => _erroDeOperacaoDoQuadro(e, s, p.atendimentoId);
}

final class DefinirPrioridadeRepository
    extends
        RepositoryBase<
          Unit,
          DefinirPrioridadeParameters,
          QuadroOperacaoError
        > {
  const DefinirPrioridadeRepository({required super.datasource});

  @override
  QuadroOperacaoError mapError(
    Object e,
    StackTrace s,
    DefinirPrioridadeParameters p,
  ) => _erroDeOperacaoDoQuadro(e, s, p.atendimentoId);
}

final class TransferirParaFluxoRepository
    extends
        RepositoryBase<
          String,
          TransferirParaFluxoParameters,
          QuadroOperacaoError
        > {
  const TransferirParaFluxoRepository({required super.datasource});

  @override
  QuadroOperacaoError mapError(
    Object e,
    StackTrace s,
    TransferirParaFluxoParameters p,
  ) => _erroDeOperacaoDoQuadro(e, s, p.atendimentoId);
}

final class ExportarQuadroRepository
    extends
        RepositoryBase<
          List<int>,
          ExportarQuadroParameters,
          QuadroOperacaoError
        > {
  const ExportarQuadroRepository({required super.datasource});

  @override
  QuadroOperacaoError mapError(
    Object e,
    StackTrace s,
    ExportarQuadroParameters p,
  ) => _erroDeOperacaoDoQuadro(e, s, null);
}

/// P5 — tudo o que é ficha usa o mesmo conjunto de erros (`FichaError`): é o
/// mesmo painel, e a tela trata as falhas no mesmo lugar.
final class ListarTimelineRepository
    extends
        RepositoryBase<
          List<EventoDaTimeline>,
          ListarTimelineParameters,
          FichaError
        > {
  const ListarTimelineRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, ListarTimelineParameters p) =>
      _erroDeFicha(e, s, p.atendimentoId);
}

final class AtendimentosDoContatoRepository
    extends
        RepositoryBase<
          List<AtendimentoResumo>,
          AtendimentosDoContatoParameters,
          FichaError
        > {
  const AtendimentosDoContatoRepository({required super.datasource});

  @override
  FichaError mapError(
    Object e,
    StackTrace s,
    AtendimentosDoContatoParameters p,
  ) => _erroDeFicha(e, s, null);
}

final class RemoverNotaRepository
    extends RepositoryBase<Unit, RemoverNotaParameters, FichaError> {
  const RemoverNotaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, RemoverNotaParameters p) =>
      _erroDeFicha(e, s, p.atendimentoId);
}

final class AtualizarEtiquetaRepository
    extends RepositoryBase<Etiqueta, AtualizarEtiquetaParameters, FichaError> {
  const AtualizarEtiquetaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, AtualizarEtiquetaParameters p) =>
      _erroDeFicha(e, s, null);
}

final class DesativarEtiquetaRepository
    extends RepositoryBase<Unit, DesativarEtiquetaParameters, FichaError> {
  const DesativarEtiquetaRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, DesativarEtiquetaParameters p) =>
      _erroDeFicha(e, s, null);
}

/// P13 — o contato da conversa. Mesmo conjunto de erros da ficha: é o mesmo
/// painel, e falhar aqui só deixa o cabeçalho com o número do atendimento.
final class ObterContatoRepository
    extends
        RepositoryBase<ContatoDaConversa, ObterContatoParameters, FichaError> {
  const ObterContatoRepository({required super.datasource});

  @override
  FichaError mapError(Object e, StackTrace s, ObterContatoParameters p) =>
      _erroDeFicha(e, s, p.atendimentoId);
}

/// P16 — conclui a revisão de uma resposta da IA.
final class MarcarRevisadoRepository
    extends
        RepositoryBase<Unit, MarcarRevisadoParameters, QuadroOperacaoError> {
  const MarcarRevisadoRepository({required super.datasource});

  @override
  QuadroOperacaoError mapError(
    Object e,
    StackTrace s,
    MarcarRevisadoParameters p,
  ) => _erroDeOperacaoDoQuadro(e, s, p.atendimentoId);
}
