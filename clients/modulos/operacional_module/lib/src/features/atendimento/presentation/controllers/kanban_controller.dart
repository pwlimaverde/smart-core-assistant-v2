import 'dart:async';

import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/parameters/list_atendimentos_parameters.dart';
import '../../domain/parameters/move_atendimento_etapa_parameters.dart';
import '../../domain/streams/atendimento_evento_stream.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import 'kanban_state.dart';

/// Controller do Kanban (fila por departamento — WS-6.2).
///
/// Orquestra estado; nenhum I/O direto (fala só com os usecases). Mover um
/// card aplica a mudança OTIMISTA na etapa local e confirma com o servidor —
/// se o RPC falhar (ex.: RBAC fino de fluxo barrando, WS-5a), reverte para o
/// snapshot anterior e devolve o erro da operação para a UI exibir (snackbar).
///
/// Também assina o stream realtime (`streamAtendimentos`, WS-6.3) para
/// refletir movimentos feitos por outros atendentes/abas: cada evento
/// `kanban.movido`/`atendimento.aberto` recarrega a fila (debounced, para não
/// disparar uma rajada de RPCs quando vários eventos chegam juntos).
final class KanbanController extends BaseController<KanbanViewModel> {
  final ListAtendimentosUsecase _listUsecase;
  final MoveAtendimentoEtapaUsecase _moveUsecase;

  /// Fonte de eventos realtime (opcional — testes de unidade do controller não
  /// precisam abrir stream).
  final AtendimentoEventoStream? eventos;

  KanbanController({
    this.eventos,
    required this._listUsecase,
    required this._moveUsecase,
  }) {
    final fonte = eventos;
    if (fonte != null) _assinarStream(fonte);
  }

  int? _departamentoAtual;
  StreamSubscription<AtendimentoEvento>? _streamSubscription;
  Timer? _debounce;

  void _assinarStream(AtendimentoEventoStream eventos) {
    _streamSubscription = eventos.abrir().listen(
      (_) {
        // Debounce curto: agrupa eventos que chegam em rajada (ex.: várias
        // mensagens seguidas) num único recarregamento da fila.
        _debounce?.cancel();
        _debounce = Timer(
          const Duration(milliseconds: 400),
          recarregarAposEvento,
        );
      },
      // Erros do stream aqui são só um sinal para não recarregar — o
      // `ChatController` já é responsável pela reconexão/backoff da conexão
      // realtime; o Kanban apenas se beneficia do stream quando ele existe.
      onError: (Object _, StackTrace _) {},
      cancelOnError: false,
    );
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    _streamSubscription?.cancel();
    return super.close();
  }

  /// Carrega (ou recarrega) a fila do departamento informado (`null` = todos).
  Future<void> carregarFila({int? departamentoId}) async {
    _departamentoAtual = departamentoId;
    await execute(() => _fetchViewModel(departamentoId));
  }

  Future<ReturnSuccessOrError<KanbanViewModel, ListAtendimentosError>>
  _fetchViewModel(int? departamentoId) async {
    final res = await _listUsecase(
      ListAtendimentosParameters(departamentoId: departamentoId),
    );
    return switch (res) {
      Success(:final value) => Success(
        KanbanViewModel(
          departamentoId: departamentoId,
          porEtapa: KanbanViewModel.agruparPorEtapa(value),
        ),
      ),
      Failure(:final error) => Failure(error),
    };
  }

  /// Aplica um evento realtime recebido no chat/stream (WS-6.3) recarregando
  /// a fila — reaproveita [carregarFila] em vez de reconciliar localmente,
  /// mantendo o Kanban simples e sempre consistente com o servidor.
  Future<void> recarregarAposEvento() =>
      carregarFila(departamentoId: _departamentoAtual);

  /// Move [atendimentoId] para [etapaDestinoId] (drop de um card numa coluna).
  ///
  /// Atualização otimista: o card já aparece na coluna destino antes da
  /// confirmação do servidor. Em caso de erro (ex.: RBAC de fluxo negado),
  /// desfaz o movimento local e devolve o erro para a UI exibir, sem perder o
  /// restante do estado carregado.
  Future<MoveAtendimentoEtapaError?> moverCard({
    required int atendimentoId,
    required int etapaOrigemId,
    required int etapaDestinoId,
  }) async {
    final atual = state;
    if (atual is! SuccessState<KanbanViewModel>) return null;
    final vm = atual.data;

    final origemLista = List<AtendimentoResumo>.of(
      vm.porEtapa[etapaOrigemId] ?? const <AtendimentoResumo>[],
    );
    final index = origemLista.indexWhere((a) => a.id == atendimentoId);
    if (index == -1) return null;
    final atendimento = origemLista.removeAt(index);

    final destinoLista = List<AtendimentoResumo>.of(
      vm.porEtapa[etapaDestinoId] ?? const <AtendimentoResumo>[],
    )..add(atendimento.copyWith(etapaAtualId: etapaDestinoId));

    final novoMapa = Map<int, List<AtendimentoResumo>>.of(vm.porEtapa)
      ..[etapaOrigemId] = origemLista
      ..[etapaDestinoId] = destinoLista;

    emit(
      SuccessState(
        vm.copyWith(porEtapa: novoMapa, movendoAtendimentoId: atendimentoId),
      ),
    );

    final res = await _moveUsecase(
      MoveAtendimentoEtapaParameters(
        atendimentoId: atendimentoId,
        etapaDestinoId: etapaDestinoId,
      ),
    );

    if (res case Failure(:final error)) {
      // Reverte: recoloca o atendimento na coluna de origem.
      final desfeitoOrigem = List<AtendimentoResumo>.of(
        novoMapa[etapaOrigemId] ?? const <AtendimentoResumo>[],
      )..add(atendimento);
      final desfeitoDestino = List<AtendimentoResumo>.of(
        novoMapa[etapaDestinoId] ?? const <AtendimentoResumo>[],
      )..removeWhere((a) => a.id == atendimentoId);
      final mapaRevertido = Map<int, List<AtendimentoResumo>>.of(novoMapa)
        ..[etapaOrigemId] = desfeitoOrigem
        ..[etapaDestinoId] = desfeitoDestino;
      emit(
        SuccessState(vm.copyWith(porEtapa: mapaRevertido, limparMovendo: true)),
      );
      return error;
    }

    final atualPosMove = state;
    if (atualPosMove is SuccessState<KanbanViewModel>) {
      emit(SuccessState(atualPosMove.data.copyWith(limparMovendo: true)));
    }
    return null;
  }
}
