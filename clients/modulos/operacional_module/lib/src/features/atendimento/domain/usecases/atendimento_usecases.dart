import 'dart:developer' as developer;

import 'package:return_success_or_error/return_success_or_error.dart';

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
  get process => (data, _) => Success(data);

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
  get process => (data, _) => Success(data);

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
        FichaAtendimento(
          catalogo: data.catalogo,
          aplicadas: data.aplicadas,
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
        UsecaseBaseCallData<Unit, Unit, AlternarEtiquetaParameters, FichaError> {
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
