import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/datasources/atendimento_datasources.dart';
import 'package:operacional_module/src/features/atendimento/data/repositories/atendimento_repositories.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/evento_timeline.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/ficha_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/ficha_controller.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/fake_gateway.dart';

/// P5 — a ficha completa: excluir nota e manter o catálogo de etiquetas.
FichaController _controller(FakeAtendimentoGateway gateway) => FichaController(
  carregar: GetFichaUsecase(
    repository: GetFichaRepository(
      datasource: GetFichaDatasource(gateway: gateway),
    ),
  ),
  criarEtiqueta: CriarEtiquetaUsecase(
    repository: CriarEtiquetaRepository(
      datasource: CriarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  alternar: AlternarEtiquetaUsecase(
    repository: AlternarEtiquetaRepository(
      datasource: AlternarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  criarNota: CriarNotaUsecase(
    repository: CriarNotaRepository(
      datasource: CriarNotaDatasource(gateway: gateway),
    ),
  ),
  definirBot: DefinirBotDaConversaUsecase(
    repository: DefinirBotDaConversaRepository(
      datasource: DefinirBotDaConversaDatasource(gateway: gateway),
    ),
  ),
  definirValorCampo: DefinirValorCampoUsecase(
    repository: DefinirValorCampoRepository(
      datasource: DefinirValorCampoDatasource(gateway: gateway),
    ),
  ),
  removerNota: RemoverNotaUsecase(
    repository: RemoverNotaRepository(
      datasource: RemoverNotaDatasource(gateway: gateway),
    ),
  ),
  atualizarEtiqueta: AtualizarEtiquetaUsecase(
    repository: AtualizarEtiquetaRepository(
      datasource: AtualizarEtiquetaDatasource(gateway: gateway),
    ),
  ),
  desativarEtiqueta: DesativarEtiquetaUsecase(
    repository: DesativarEtiquetaRepository(
      datasource: DesativarEtiquetaDatasource(gateway: gateway),
    ),
  ),
);

void main() {
  group('ficha completa (P5)', () {
    test('excluir nota manda o atendimento junto e recarrega a ficha', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);
      await controller.abrir(9);
      final recargas = gateway.chamadasFicha;

      final erro = await controller.removerNota(3);

      expect(erro, isNull);
      // O atendimento vai junto: é o que impede apagar nota de outra conversa.
      expect(gateway.acoesDaFicha, contains('removerNota:3:9'));
      expect(gateway.chamadasFicha, recargas + 1);
      await controller.close();
    });

    test('editar e desativar etiqueta chegam ao servidor', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);
      await controller.abrir(9);

      await controller.atualizarEtiqueta(id: 4, nome: 'Urgente');
      await controller.desativarEtiqueta(4);

      expect(gateway.acoesDaFicha, [
        'atualizarEtiqueta:4:Urgente',
        'desativarEtiqueta:4',
      ]);
      await controller.close();
    });

    test('a timeline chega ordenada como o servidor mandou', () async {
      final gateway = FakeAtendimentoGateway()
        ..timeline = [
          EventoDaTimeline(
            tipo: 'aberto',
            quando: DateTime(2026, 1, 1),
            descricao: 'Conversa iniciada',
            automatico: true,
          ),
          EventoDaTimeline(
            tipo: 'nota',
            quando: DateTime(2026, 1, 2),
            descricao: 'cliente pediu retorno',
            autor: 'Ana',
          ),
        ];
      final usecase = ListarTimelineUsecase(
        repository: ListarTimelineRepository(
          datasource: ListarTimelineDatasource(gateway: gateway),
        ),
      );

      final res = await usecase(
        const ListarTimelineParameters(atendimentoId: 9),
      );

      final eventos = switch (res) {
        Success(:final value) => value,
        Failure() => <EventoDaTimeline>[],
      };
      expect(eventos.map((e) => e.tipo), ['aberto', 'nota']);
      expect(eventos.last.autor, 'Ana');
    });

    test('o histórico do contato usa o mesmo resumo do quadro', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 5, etapaAtualId: 10)],
      );
      final usecase = AtendimentosDoContatoUsecase(
        repository: AtendimentosDoContatoRepository(
          datasource: AtendimentosDoContatoDatasource(gateway: gateway),
        ),
      );

      final res = await usecase(
        const AtendimentosDoContatoParameters(contatoId: 2),
      );

      final itens = switch (res) {
        Success(:final value) => value,
        Failure() => <AtendimentoResumo>[],
      };
      expect(itens.single.id, 5);
    });
  });
}
