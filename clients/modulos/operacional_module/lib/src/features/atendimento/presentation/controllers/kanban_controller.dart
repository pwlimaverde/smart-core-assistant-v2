import 'dart:async';

import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../domain/errors/atendimento_errors.dart';
import '../../domain/model/atendimento_evento.dart';
import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/quadro.dart';
import '../../domain/parameters/list_atendimentos_parameters.dart';
import '../../domain/parameters/move_atendimento_etapa_parameters.dart';
import '../../domain/parameters/quadro_parameters.dart';
import '../../domain/streams/atendimento_evento_stream.dart';
import '../../domain/usecases/atendimento_usecases.dart';
import 'kanban_state.dart';

/// Controller do Kanban.
///
/// Orquestra estado; nenhum I/O direto (fala só com os usecases). Mover um
/// card aplica a mudança OTIMISTA na etapa local e confirma com o servidor —
/// se o RPC falhar (ex.: RBAC fino de fluxo barrando), reverte para o snapshot
/// anterior e devolve o erro da operação para a UI exibir.
///
/// Também assina o stream realtime para refletir movimentos feitos por outros
/// atendentes/abas: cada evento recarrega a fila (debounced, para não disparar
/// uma rajada de RPCs quando vários eventos chegam juntos).
// ignore_for_file: prefer_initializing_formals

/// B5 — uma conversa que o rodízio atribuiu a quem está logado.
typedef AtribuicaoRecebida = ({int atendimentoId, String fluxo});

final class KanbanController extends BaseController<KanbanViewModel> {
  final ListAtendimentosUsecase _listUsecase;
  final MoveAtendimentoEtapaUsecase _moveUsecase;
  final ListFluxosUsecase _fluxosUsecase;
  final ListColunasUsecase _colunasUsecase;
  final SetAtendimentoStatusUsecase _statusUsecase;

  /// Fonte de eventos realtime (opcional — testes de unidade do controller não
  /// precisam abrir stream).
  final AtendimentoEventoStream? eventos;

  /// B5 — quem é o usuário da sessão, para reconhecer a conversa atribuída a
  /// ele. Entra por função, como o menu: a sessão é do `login_module`, que
  /// este módulo não conhece.
  final int? Function()? usuarioAtual;

  final _atribuicoes = StreamController<AtribuicaoRecebida>.broadcast();

  /// Conversas que o rodízio acabou de atribuir **a quem está logado**.
  ///
  /// As dos colegas não aparecem aqui: o quadro recarrega para todo mundo, mas
  /// o aviso é só para quem recebeu.
  Stream<AtribuicaoRecebida> get atribuicoes => _atribuicoes.stream;

  KanbanController({
    this.eventos,
    this.usuarioAtual,
    required ListAtendimentosUsecase listUsecase,
    required MoveAtendimentoEtapaUsecase moveUsecase,
    required ListFluxosUsecase fluxosUsecase,
    required ListColunasUsecase colunasUsecase,
    required SetAtendimentoStatusUsecase statusUsecase,
  }) : _listUsecase = listUsecase,
       _moveUsecase = moveUsecase,
       _fluxosUsecase = fluxosUsecase,
       _colunasUsecase = colunasUsecase,
       _statusUsecase = statusUsecase {
    final fonte = eventos;
    if (fonte != null) _assinarStream(fonte);
  }

  int? _fluxoAtual;
  List<FluxoDoQuadro> _fluxos = const [];
  List<ColunaDoQuadro> _colunas = const [];
  StreamSubscription<AtendimentoEvento>? _streamSubscription;
  Timer? _debounce;

  void _assinarStream(AtendimentoEventoStream eventos) {
    _streamSubscription = eventos.abrir().listen(
      (evento) {
        _avisarSeForMinha(evento);
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

  /// B5 — repassa o aviso de atribuição quando o destinatário é a sessão atual.
  void _avisarSeForMinha(AtendimentoEvento evento) {
    if (evento.tipo != 'atendimento.atribuido') return;
    final eu = usuarioAtual?.call();
    final destinatario = evento.payload['usuario_id'];
    final atendimentoId = evento.atendimentoId;
    if (eu == null || atendimentoId == null) return;
    if (destinatario is! num || destinatario.toInt() != eu) return;
    final AtribuicaoRecebida atribuicao = (
      atendimentoId: atendimentoId,
      fluxo: '${evento.payload['fluxo_nome'] ?? ''}',
    );
    _atribuicoes.add(atribuicao);
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    _streamSubscription?.cancel();
    _atribuicoes.close();
    return super.close();
  }

  /// Monta o quadro: descobre os fluxos, abre um deles e carrega as conversas.
  ///
  /// A lista de fluxos só é buscada uma vez — é configuração, muda raramente, e
  /// rebuscá-la a cada recarga da fila triplicaria as idas ao servidor durante
  /// uma rajada de mensagens.
  Future<void> carregar({int? fluxoId}) async {
    if (_fluxos.isEmpty) {
      final res = await _fluxosUsecase(noParams);
      if (res case Success(:final value)) _fluxos = value;
    }

    final escolhido =
        fluxoId ??
        _fluxoAtual ??
        (_fluxos.isNotEmpty ? _fluxos.first.id : null);
    if (escolhido != _fluxoAtual) {
      _fluxoAtual = escolhido;
      _colunas = const [];
    }

    if (escolhido != null && _colunas.isEmpty) {
      final res = await _colunasUsecase(
        ListColunasParameters(fluxoId: escolhido),
      );
      if (res case Success(:final value)) _colunas = value;
    }

    await execute(() => _montar(escolhido));
  }

  /// Troca o quadro aberto.
  Future<void> abrirQuadro(int fluxoId) => carregar(fluxoId: fluxoId);

  Future<ReturnSuccessOrError<KanbanViewModel, ListAtendimentosError>> _montar(
    int? fluxoId,
  ) async {
    // Sem filtro de status: o quadro mostra a conversa em qualquer coluna, e
    // filtrar por "fila" deixaria as colunas de trabalho e finalização vazias.
    final res = await _listUsecase(
      const ListAtendimentosParameters(status: ''),
    );
    return switch (res) {
      Success(:final value) => Success(
        KanbanViewModel(
          fluxoId: fluxoId,
          fluxos: _fluxos,
          colunas: _colunas,
          porEtapa: KanbanViewModel.agruparPorEtapa(value),
        ),
      ),
      Failure(:final error) => Failure(error),
    };
  }

  /// B6 — a conversa foi aberta: o número do cartão some na hora, sem esperar
  /// a próxima recarga. O servidor marca a leitura quando o fim da conversa
  /// aparece; se a marcação falhar, a próxima recarga devolve o número.
  void zerarNaoLidas(int atendimentoId) {
    final atual = state;
    if (atual is! SuccessState<KanbanViewModel>) return;
    final porEtapa = atual.data.porEtapa;
    final temNaoLidas = porEtapa.values.any(
      (lista) => lista.any((a) => a.id == atendimentoId && a.naoLidas > 0),
    );
    if (!temNaoLidas) return;
    final mapa = {
      for (final MapEntry(key: etapa, value: lista) in porEtapa.entries)
        etapa: [
          for (final a in lista)
            a.id == atendimentoId ? a.copyWith(naoLidas: 0) : a,
        ],
    };
    emit(SuccessState(atual.data.copyWith(porEtapa: mapa)));
  }

  /// Aplica um evento realtime recarregando a fila — reaproveita [carregar] em
  /// vez de reconciliar localmente, mantendo o quadro sempre consistente com o
  /// servidor.
  Future<void> recarregarAposEvento() => carregar();

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

    // O status acompanha a coluna, aqui e no servidor. Aplicar já no otimismo
    // evita uma ida extra só para reler o que se sabe -- e evita o cartão
    // aparecer na coluna de finalização ainda marcado como "na fila".
    final destino = vm.colunas.where((c) => c.id == etapaDestinoId).firstOrNull;
    final destinoLista =
        List<AtendimentoResumo>.of(
          vm.porEtapa[etapaDestinoId] ?? const <AtendimentoResumo>[],
        )..add(
          atendimento.copyWith(
            etapaAtualId: etapaDestinoId,
            status: destino?.statusResultante,
          ),
        );

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

  /// Muda o estado do atendimento. O servidor move o cartão junto; aqui só se
  /// recarrega para ver onde ele parou.
  Future<SetStatusError?> definirStatus({
    required int atendimentoId,
    required String status,
    String motivo = '',
  }) async {
    final res = await _statusUsecase(
      SetAtendimentoStatusParameters(
        atendimentoId: atendimentoId,
        status: status,
        motivo: motivo,
      ),
    );
    if (res case Failure(:final error)) return error;
    await recarregarAposEvento();
    return null;
  }
}
