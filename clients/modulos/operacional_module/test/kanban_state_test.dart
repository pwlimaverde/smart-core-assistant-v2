import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_state.dart';

AtendimentoResumo _atendimento({required int id, int? etapaAtualId}) =>
    AtendimentoResumo(
      id: id,
      contatoId: id,
      status: 'fila',
      etapaAtualId: etapaAtualId,
      assunto: 'Assunto $id',
      prioridade: 'normal',
      dataInicio: DateTime(2026, 1, 1),
    );

void main() {
  group('KanbanViewModel.agruparPorEtapa', () {
    test('agrupa atendimentos pela etapaAtualId', () {
      final atendimentos = [
        _atendimento(id: 1, etapaAtualId: 10),
        _atendimento(id: 2, etapaAtualId: 10),
        _atendimento(id: 3, etapaAtualId: 20),
      ];

      final grupos = KanbanViewModel.agruparPorEtapa(atendimentos);

      expect(grupos[10]?.map((a) => a.id), [1, 2]);
      expect(grupos[20]?.map((a) => a.id), [3]);
    });

    test('atendimento sem etapa cai na chave semEtapa', () {
      final atendimentos = [_atendimento(id: 1, etapaAtualId: null)];

      final grupos = KanbanViewModel.agruparPorEtapa(atendimentos);

      expect(grupos[KanbanViewModel.semEtapa]?.single.id, 1);
    });
  });

  group('AtendimentoResumo.copyWith', () {
    test('atualiza etapaAtualId preservando os demais campos', () {
      final original = _atendimento(id: 1, etapaAtualId: 10);

      final movido = original.copyWith(etapaAtualId: 20);

      expect(movido.id, original.id);
      expect(movido.etapaAtualId, 20);
      expect(movido.assunto, original.assunto);
    });
  });
}
