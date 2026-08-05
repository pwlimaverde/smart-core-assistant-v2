import 'package:meta/meta.dart';

import '../../domain/model/atendimento_resumo.dart';
import '../../domain/model/quadro.dart';

/// View-model composto do Kanban: as colunas do quadro e os atendimentos já
/// distribuídos nelas.
///
/// As colunas vêm do **fluxo cadastrado**, não dos atendimentos existentes.
/// Derivá-las dos dados fazia uma coluna vazia desaparecer — não havia para
/// onde arrastar —, e um quadro sem conversa nenhuma abria em branco, como se
/// estivesse quebrado. Era o que acontecia numa conta nova.
@immutable
final class KanbanViewModel {
  /// Quadro aberto agora (`null` = ainda não escolhido / nenhum disponível).
  final int? fluxoId;

  /// Quadros que o atendente pode abrir.
  final List<FluxoDoQuadro> fluxos;

  /// Colunas do quadro aberto, na ordem em que aparecem.
  final List<ColunaDoQuadro> colunas;

  /// Atendimentos agrupados por `etapaAtualId` (chave [semEtapa] = conversa que
  /// ainda não foi roteada para coluna nenhuma).
  final Map<int, List<AtendimentoResumo>> porEtapa;

  /// Id do atendimento em movimentação otimista (drag em andamento/pendente de
  /// confirmação do servidor) — usado para não duplicar a UI durante o RPC.
  final int? movendoAtendimentoId;

  const KanbanViewModel({
    this.fluxoId,
    this.fluxos = const [],
    this.colunas = const [],
    required this.porEtapa,
    this.movendoAtendimentoId,
  });

  static const semEtapa = -1;

  /// Conversas fora de qualquer coluna do quadro.
  ///
  /// São as que chegaram antes de o fluxo existir, ou que apontam para uma
  /// coluna já removida. Precisam de um lugar visível: escondê-las faria
  /// desaparecer atendimento de verdade, que é o pior desfecho possível aqui.
  List<AtendimentoResumo> get semColuna {
    final conhecidas = colunas.map((c) => c.id).toSet();
    return [
      for (final entrada in porEtapa.entries)
        if (!conhecidas.contains(entrada.key)) ...entrada.value,
    ];
  }

  bool get temQuadro => colunas.isNotEmpty;

  KanbanViewModel copyWith({
    int? fluxoId,
    List<FluxoDoQuadro>? fluxos,
    List<ColunaDoQuadro>? colunas,
    Map<int, List<AtendimentoResumo>>? porEtapa,
    int? movendoAtendimentoId,
    bool limparMovendo = false,
  }) => KanbanViewModel(
    fluxoId: fluxoId ?? this.fluxoId,
    fluxos: fluxos ?? this.fluxos,
    colunas: colunas ?? this.colunas,
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
