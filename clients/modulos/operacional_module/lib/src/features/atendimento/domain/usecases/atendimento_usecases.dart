import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

import '../parameters/definir_valor_campo_parameters.dart';
import '../parameters/iniciar_atendimento_parameters.dart';
import '../model/atendimento_iniciado.dart';
import '../errors/atendimento_errors.dart';
import '../model/atendimento_resumo.dart';
import '../model/mensagem_thread.dart';
import '../parameters/get_thread_parameters.dart';
import '../parameters/list_atendimentos_parameters.dart';
import '../parameters/move_atendimento_etapa_parameters.dart';
import '../model/ficha.dart';
import '../model/quadro.dart';
import '../parameters/ficha_parameters.dart';
import '../parameters/quadro_parameters.dart';
import '../parameters/send_outbound_message_parameters.dart';
import '../model/midia_mensagem.dart';
import '../parameters/presenca_parameters.dart';
import '../parameters/quadro_operacao_parameters.dart';
import '../model/evento_timeline.dart';
import '../model/contato_da_conversa.dart';

/// Os quatro casos de uso do atendimento.
///
/// O `process` do thread carrega a única regra de ordenação da feature (ordem
/// cronológica), e ela está aqui — não na tela — porque vale para as duas fontes:
/// no desktop, uma mensagem pendente de sync tem id negativo provisório, e a
/// ordem que o índice local devolve não é necessariamente a que o chat espera.
/// Os outros três são passthrough e existem pelo `onUnexpected`: é ele que
/// garante que um bug de mapeamento chegue como erro previsto, e não como exceção
/// escapando para o controller.

void _logBug(String operacao, Object exception, StackTrace stackTrace) =>
    developer.log(
      'process de $operacao quebrou',
      name: 'operacional_module.atendimento',
      error: exception,
      stackTrace: stackTrace,
    );

/// Lista a fila, com a ordenação que o Kanban espera.
final class ListAtendimentosUsecase
    extends
        UsecaseBaseCallData<
          List<AtendimentoResumo>,
          List<AtendimentoResumo>,
          ListAtendimentosParameters,
          ListAtendimentosError
        > {
  const ListAtendimentosUsecase({required super.repository});

  @override
  ProcessData<
    List<AtendimentoResumo>,
    List<AtendimentoResumo>,
    ListAtendimentosParameters,
    ListAtendimentosError
  >
  get process => _process;

  @override
  ListAtendimentosError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listAtendimentos', exception, stackTrace);
    return const ListAtendimentosInesperado();
  }

  /// Passthrough, com a lista protegida contra mutação acidental pelas telas.
  ///
  /// A ordenação **não** é imposta aqui de propósito: `prioridade` é texto livre
  /// no contrato (`'alta'`, `'normal'`, …), sem ordem total definida no domínio,
  /// e reordenar por ele exigiria inventar essa ordem. A ordem em que a fonte
  /// entrega (servidor no Web, índice SQLite no desktop) é a que as telas já
  /// consomem.
  static ReturnSuccessOrError<List<AtendimentoResumo>, ListAtendimentosError>
  _process(
    List<AtendimentoResumo> data,
    ListAtendimentosParameters parameters,
  ) => Success(List.unmodifiable(data));
}

/// Carrega o thread do chat em ordem cronológica.
final class GetThreadUsecase
    extends
        UsecaseBaseCallData<
          List<MensagemThread>,
          List<MensagemThread>,
          GetThreadParameters,
          GetThreadError
        > {
  const GetThreadUsecase({required super.repository});

  @override
  ProcessData<
    List<MensagemThread>,
    List<MensagemThread>,
    GetThreadParameters,
    GetThreadError
  >
  get process => _process;

  @override
  GetThreadError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getThread', exception, stackTrace);
    return const GetThreadInesperado();
  }

  /// Ordem cronológica ascendente: a bolha mais antiga no topo. No desktop, uma
  /// mensagem pendente de sync tem id negativo provisório, então ordenar por id
  /// colocaria as mensagens não enviadas antes de tudo — o critério é o
  /// timestamp.
  static ReturnSuccessOrError<List<MensagemThread>, GetThreadError> _process(
    List<MensagemThread> data,
    GetThreadParameters parameters,
  ) {
    final ordenadas = [...data]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return Success(List.unmodifiable(ordenadas));
  }
}

/// Move um atendimento de etapa no Kanban.
final class MoveAtendimentoEtapaUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          MoveAtendimentoEtapaParameters,
          MoveAtendimentoEtapaError
        > {
  const MoveAtendimentoEtapaUsecase({required super.repository});

  @override
  ProcessData<
    Unit,
    Unit,
    MoveAtendimentoEtapaParameters,
    MoveAtendimentoEtapaError
  >
  get process => _process;

  @override
  MoveAtendimentoEtapaError onUnexpected(
    Object exception,
    StackTrace stackTrace,
  ) {
    _logBug('moveAtendimentoEtapa', exception, stackTrace);
    return const MoveEtapaInesperado();
  }

  static ReturnSuccessOrError<Unit, MoveAtendimentoEtapaError> _process(
    Unit data,
    MoveAtendimentoEtapaParameters parameters,
  ) => const Success(unit);
}

/// C3 — abre um atendimento a partir de um cliente já cadastrado.
final class IniciarAtendimentoUsecase
    extends
        UsecaseBaseCallData<
          AtendimentoIniciado,
          AtendimentoIniciado,
          IniciarAtendimentoParameters,
          IniciarAtendimentoError
        > {
  const IniciarAtendimentoUsecase({required super.repository});

  @override
  ProcessData<
    AtendimentoIniciado,
    AtendimentoIniciado,
    IniciarAtendimentoParameters,
    IniciarAtendimentoError
  >
  get process => _process;

  @override
  IniciarAtendimentoError onUnexpected(
    Object exception,
    StackTrace stackTrace,
  ) {
    _logBug('iniciarAtendimento', exception, stackTrace);
    return const IniciarAtendimentoInesperado();
  }

  /// Confere o que voltou, não o que foi pedido.
  ///
  /// O `process` do RSOE roda **depois** do datasource (fetch → curto-circuito
  /// no erro → process), então validar a entrada aqui não pouparia a ida ao
  /// servidor — só daria a impressão de poupar. Quem barra pedido incompleto é
  /// a tela, que desabilita o botão, e o servidor, que recusa com
  /// `invalid_argument`.
  ///
  /// O que sobra para este ponto é o contrato de saída: um atendimento sem id
  /// não é um atendimento, e devolvê-lo como sucesso faria a tela navegar para
  /// uma conversa que não existe.
  static ReturnSuccessOrError<AtendimentoIniciado, IniciarAtendimentoError>
  _process(AtendimentoIniciado data, IniciarAtendimentoParameters parameters) {
    if (data.atendimentoId <= 0) {
      return const Failure(IniciarAtendimentoInesperado());
    }
    return Success(data);
  }
}

/// N9 E13 — preenche um campo do cartão na ficha.
final class DefinirValorCampoUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DefinirValorCampoParameters,
          DefinirValorCampoError
        > {
  const DefinirValorCampoUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DefinirValorCampoParameters, DefinirValorCampoError>
  get process =>
      (data, _) => Success(data);

  @override
  DefinirValorCampoError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('definirValorCampo', exception, stackTrace);
    return const ValorCampoInesperado();
  }
}

/// Envia uma mensagem do atendente.
final class SendOutboundMessageUsecase
    extends
        UsecaseBaseCallData<
          int,
          int,
          SendOutboundMessageParameters,
          SendOutboundMessageError
        > {
  const SendOutboundMessageUsecase({required super.repository});

  @override
  ProcessData<int, int, SendOutboundMessageParameters, SendOutboundMessageError>
  get process => _process;

  @override
  SendOutboundMessageError onUnexpected(
    Object exception,
    StackTrace stackTrace,
  ) {
    _logBug('sendOutboundMessage', exception, stackTrace);
    return const SendMessageInesperado();
  }

  /// Passthrough: o id persistido é o resultado.
  ///
  /// Validar conteúdo vazio **não** cabe aqui — o `process` roda depois do fetch,
  /// quando a mensagem já foi enviada. Essa checagem é da apresentação, que
  /// desabilita o botão, e do servidor, que responde `invalidArgument` e vira
  /// [SendMessageConteudoInvalido] no `mapError`.
  static ReturnSuccessOrError<int, SendOutboundMessageError> _process(
    int data,
    SendOutboundMessageParameters parameters,
  ) => Success(data);
}

final class ListFluxosUsecase
    extends
        UsecaseBaseCallData<
          List<FluxoDoQuadro>,
          List<FluxoDoQuadro>,
          NoParams,
          QuadroError
        > {
  const ListFluxosUsecase({required super.repository});

  @override
  ProcessData<List<FluxoDoQuadro>, List<FluxoDoQuadro>, NoParams, QuadroError>
  get process =>
      (data, _) => Success(data);

  @override
  QuadroError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listFluxos', exception, stackTrace);
    return const QuadroInesperado();
  }
}

final class ListColunasUsecase
    extends
        UsecaseBaseCallData<
          List<ColunaDoQuadro>,
          List<ColunaDoQuadro>,
          ListColunasParameters,
          QuadroError
        > {
  const ListColunasUsecase({required super.repository});

  /// Ordena aqui, e não na tela: a ordem das colunas é regra do quadro, e uma
  /// tela que reordena por conta própria mostraria um fluxo que não existe.
  @override
  ProcessData<
    List<ColunaDoQuadro>,
    List<ColunaDoQuadro>,
    ListColunasParameters,
    QuadroError
  >
  get process =>
      (data, _) => Success(List.of(data)..sort((a, b) => a.ordem - b.ordem));

  @override
  QuadroError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listColunas', exception, stackTrace);
    return const QuadroInesperado();
  }
}

final class SetAtendimentoStatusUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          SetAtendimentoStatusParameters,
          SetStatusError
        > {
  const SetAtendimentoStatusUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, SetAtendimentoStatusParameters, SetStatusError>
  get process =>
      (data, _) => Success(data);

  @override
  SetStatusError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('setAtendimentoStatus', exception, stackTrace);
    return const SetStatusInesperado();
  }
}

final class GetFichaUsecase
    extends
        UsecaseBaseCallData<
          FichaAtendimento,
          FichaAtendimento,
          AtendimentoIdParameters,
          FichaError
        > {
  const GetFichaUsecase({required super.repository});

  /// Ordena as notas da mais recente para a mais antiga.
  ///
  /// O servidor já devolve assim, mas é a apresentação que decide: quem abre a
  /// ficha quer ver o que aconteceu por último, não o começo da história.
  @override
  ProcessData<
    FichaAtendimento,
    FichaAtendimento,
    AtendimentoIdParameters,
    FichaError
  >
  get process =>
      (data, _) => Success(
        data.copyWith(
          notas: List.of(data.notas)
            ..sort((a, b) => b.criadoEm.compareTo(a.criadoEm)),
        ),
      );

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('getFicha', exception, stackTrace);
    return const FichaInesperado();
  }
}

final class CriarEtiquetaUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, CriarEtiquetaParameters, FichaError> {
  const CriarEtiquetaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarEtiquetaParameters, FichaError> get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('criarEtiqueta', exception, stackTrace);
    return const FichaInesperado();
  }
}

final class AlternarEtiquetaUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          AlternarEtiquetaParameters,
          FichaError
        > {
  const AlternarEtiquetaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, AlternarEtiquetaParameters, FichaError> get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('alternarEtiqueta', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// B6 (N9 E4) — marca como lidas as mensagens do contato; devolve quantas.
final class MarcarAtendimentoLidoUsecase
    extends
        UsecaseBaseCallData<
          int,
          int,
          MarcarAtendimentoLidoParameters,
          FichaError
        > {
  const MarcarAtendimentoLidoUsecase({required super.repository});

  @override
  ProcessData<int, int, MarcarAtendimentoLidoParameters, FichaError>
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('marcarAtendimentoLido', exception, stackTrace);
    return const FichaInesperado();
  }
}

final class DefinirBotDaConversaUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DefinirBotDaConversaParameters,
          FichaError
        > {
  const DefinirBotDaConversaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DefinirBotDaConversaParameters, FichaError>
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('definirBotDaConversa', exception, stackTrace);
    return const FichaInesperado();
  }
}

final class CriarNotaUsecase
    extends UsecaseBaseCallData<Unit, Unit, CriarNotaParameters, FichaError> {
  const CriarNotaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, CriarNotaParameters, FichaError> get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('criarNota', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// P3 — "digitando..." do atendente.
final class EnviarPresencaUsecase
    extends
        UsecaseBaseCallData<bool, bool, EnviarPresencaParameters, PresencaError> {
  const EnviarPresencaUsecase({required super.repository});

  @override
  ProcessData<bool, bool, EnviarPresencaParameters, PresencaError>
  get process =>
      (data, _) => Success(data);

  @override
  PresencaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('enviarPresenca', exception, stackTrace);
    return const PresencaInesperado();
  }
}

/// P3 — galeria de arquivos da conversa.
final class ListarMidiasUsecase
    extends
        UsecaseBaseCallData<
          List<MidiaMensagem>,
          List<MidiaMensagem>,
          ListarMidiasParameters,
          MidiasError
        > {
  const ListarMidiasUsecase({required super.repository});

  @override
  ProcessData<
    List<MidiaMensagem>,
    List<MidiaMensagem>,
    ListarMidiasParameters,
    MidiasError
  >
  get process =>
      (data, _) => Success(data);

  @override
  MidiasError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listarMidias', exception, stackTrace);
    return const MidiasInesperado();
  }
}

/// P3 — anexo e áudio na conversa.
final class EnviarMidiaUsecase
    extends
        UsecaseBaseCallData<int, int, EnviarMidiaParameters, EnviarMidiaError> {
  const EnviarMidiaUsecase({required super.repository});

  @override
  ProcessData<int, int, EnviarMidiaParameters, EnviarMidiaError> get process =>
      (data, _) => Success(data);

  @override
  EnviarMidiaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('enviarMidia', exception, stackTrace);
    return const EnviarMidiaInesperado();
  }
}

/// P4 — dono da conversa.
final class AtribuirAtendimentoUsecase
    extends
        UsecaseBaseCallData<
          bool,
          bool,
          AtribuirAtendimentoParameters,
          QuadroOperacaoError
        > {
  const AtribuirAtendimentoUsecase({required super.repository});

  @override
  ProcessData<bool, bool, AtribuirAtendimentoParameters, QuadroOperacaoError>
  get process =>
      (data, _) => Success(data);

  @override
  QuadroOperacaoError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('atribuirAtendimento', exception, stackTrace);
    return const QuadroOperacaoInesperado();
  }
}

/// P4 — urgência do cartão.
final class DefinirPrioridadeUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DefinirPrioridadeParameters,
          QuadroOperacaoError
        > {
  const DefinirPrioridadeUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DefinirPrioridadeParameters, QuadroOperacaoError>
  get process =>
      (data, _) => Success(data);

  @override
  QuadroOperacaoError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('definirPrioridade', exception, stackTrace);
    return const QuadroOperacaoInesperado();
  }
}

/// P4 — transferência de fluxo feita a mão.
final class TransferirParaFluxoUsecase
    extends
        UsecaseBaseCallData<
          String,
          String,
          TransferirParaFluxoParameters,
          QuadroOperacaoError
        > {
  const TransferirParaFluxoUsecase({required super.repository});

  @override
  ProcessData<String, String, TransferirParaFluxoParameters, QuadroOperacaoError>
  get process =>
      (data, _) => Success(data);

  @override
  QuadroOperacaoError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('transferirParaFluxo', exception, stackTrace);
    return const QuadroOperacaoInesperado();
  }
}

/// P4 — o quadro em CSV.
final class ExportarQuadroUsecase
    extends
        UsecaseBaseCallData<
          List<int>,
          List<int>,
          ExportarQuadroParameters,
          QuadroOperacaoError
        > {
  const ExportarQuadroUsecase({required super.repository});

  @override
  ProcessData<List<int>, List<int>, ExportarQuadroParameters, QuadroOperacaoError>
  get process =>
      (data, _) => Success(data);

  @override
  QuadroOperacaoError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('exportarQuadro', exception, stackTrace);
    return const QuadroOperacaoInesperado();
  }
}

/// P5 — a linha do tempo do atendimento.
final class ListarTimelineUsecase
    extends
        UsecaseBaseCallData<
          List<EventoDaTimeline>,
          List<EventoDaTimeline>,
          ListarTimelineParameters,
          FichaError
        > {
  const ListarTimelineUsecase({required super.repository});

  @override
  ProcessData<
    List<EventoDaTimeline>,
    List<EventoDaTimeline>,
    ListarTimelineParameters,
    FichaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('listarTimeline', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// P5 — as outras conversas do mesmo contato.
final class AtendimentosDoContatoUsecase
    extends
        UsecaseBaseCallData<
          List<AtendimentoResumo>,
          List<AtendimentoResumo>,
          AtendimentosDoContatoParameters,
          FichaError
        > {
  const AtendimentosDoContatoUsecase({required super.repository});

  @override
  ProcessData<
    List<AtendimentoResumo>,
    List<AtendimentoResumo>,
    AtendimentosDoContatoParameters,
    FichaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('atendimentosDoContato', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// P5 — apaga uma nota interna.
final class RemoverNotaUsecase
    extends
        UsecaseBaseCallData<Unit, Unit, RemoverNotaParameters, FichaError> {
  const RemoverNotaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, RemoverNotaParameters, FichaError> get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('removerNota', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// P5 — renomeia/recolore uma etiqueta do catálogo.
final class AtualizarEtiquetaUsecase
    extends
        UsecaseBaseCallData<
          Etiqueta,
          Etiqueta,
          AtualizarEtiquetaParameters,
          FichaError
        > {
  const AtualizarEtiquetaUsecase({required super.repository});

  @override
  ProcessData<Etiqueta, Etiqueta, AtualizarEtiquetaParameters, FichaError>
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('atualizarEtiqueta', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// P5 — tira a etiqueta do catálogo.
final class DesativarEtiquetaUsecase
    extends
        UsecaseBaseCallData<
          Unit,
          Unit,
          DesativarEtiquetaParameters,
          FichaError
        > {
  const DesativarEtiquetaUsecase({required super.repository});

  @override
  ProcessData<Unit, Unit, DesativarEtiquetaParameters, FichaError>
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('desativarEtiqueta', exception, stackTrace);
    return const FichaInesperado();
  }
}

/// P13 — o contato da conversa, para o cabeçalho.
final class ObterContatoUsecase
    extends
        UsecaseBaseCallData<
          ContatoDaConversa,
          ContatoDaConversa,
          ObterContatoParameters,
          FichaError
        > {
  const ObterContatoUsecase({required super.repository});

  @override
  ProcessData<
    ContatoDaConversa,
    ContatoDaConversa,
    ObterContatoParameters,
    FichaError
  >
  get process =>
      (data, _) => Success(data);

  @override
  FichaError onUnexpected(Object exception, StackTrace stackTrace) {
    _logBug('obterContato', exception, stackTrace);
    return const FichaInesperado();
  }
}
