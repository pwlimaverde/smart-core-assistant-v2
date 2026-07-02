import 'package:meta/meta.dart';

import '../../domain/model/atendimento_resumo.dart';

/// View-model composto do Kanban (WS-6.2): os atendimentos já agrupados por
/// etapa. A UI (colunas) só itera [porEtapa] — nenhuma lógica de agrupamento
/// na tela.
@immutable
final class KanbanViewModel {
  /// Departamento filtrado atualmente (`null` = todos).
  final int? departamentoId;

  /// Atendimentos agrupados por `etapaAtualId` (chave `-1` = sem etapa/fila
  /// ainda não roteada — exibidos numa coluna "Fila" própria).
  final Map<int, List<AtendimentoResumo>> porEtapa;

  /// Id do atendimento em movimentação otimista (drag em andamento/pendente de
  /// confirmação do servidor) — usado para não duplicar a UI durante o RPC.
  final int? movendoAtendimentoId;

  const KanbanViewModel({
    this.departamentoId,
    required this.porEtapa,
    this.movendoAtendimentoId,
  });

  static const semEtapa = -1;

  KanbanViewModel copyWith({
    int? departamentoId,
    bool limparDepartamento = false,
    Map<int, List<AtendimentoResumo>>? porEtapa,
    int? movendoAtendimentoId,
    bool limparMovendo = false,
  }) => KanbanViewModel(
    departamentoId: limparDepartamento
        ? null
        : (departamentoId ?? this.departamentoId),
    porEtapa: porEtapa ?? this.porEtapa,
    movendoAtendimentoId: limparMovendo
        ? null
        : (movendoAtendimentoId ?? this.movendoAtendimentoId),
  );

  /// Agrupa uma lista plana de atendimentos por etapa (helper reaproveitado
  /// pelo controller a cada fetch/evento realtime).
  static Map<int, List<AtendimentoResumo>> agruparPorEtapa(
    List<AtendimentoResumo> atendimentos,
  ) {
    final grupos = <int, List<AtendimentoResumo>>{};
    for (final a in atendimentos) {
      final chave = a.etapaAtualId ?? semEtapa;
      grupos.putIfAbsent(chave, () => []).add(a);
    }
    return grupos;
  }
}
