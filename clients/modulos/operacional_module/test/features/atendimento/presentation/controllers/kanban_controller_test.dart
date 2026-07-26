import 'package:api_client/api_client.dart' show GrpcError;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_state.dart';
import 'package:presentation_module/presentation_module.dart';

import '../../support/fake_gateway.dart';

/// Monta o controller sobre a cadeia real (datasource + repositório + usecase),
/// trocando só o gateway de plataforma.
KanbanController _controller(
  FakeAtendimentoGateway gateway, {
  bool comStream = false,
}) {
  final u = usecasesSobre(gateway);
  return KanbanController(
    listUsecase: u.list,
    moveUsecase: u.move,
    eventos: comStream ? u.eventos : null,
  );
}

void main() {
  group('carregarFila', () {
    blocTest<KanbanController, ViewState<KanbanViewModel>>(
      'sucesso: emite [Loading, Success] agrupando por etapa',
      build: () => _controller(
        FakeAtendimentoGateway(
          fila: [
            atendimentoDeTeste(id: 1, etapaAtualId: 10),
            atendimentoDeTeste(id: 2, etapaAtualId: 20),
          ],
        ),
      ),
      act: (c) => c.carregarFila(),
      expect: () => [
        isA<LoadingState<KanbanViewModel>>(),
        isA<SuccessState<KanbanViewModel>>().having(
          (s) => s.data.porEtapa.keys,
          'etapas',
          containsAll([10, 20]),
        ),
      ],
    );

    blocTest<KanbanController, ViewState<KanbanViewModel>>(
      'erro do backend: emite [Loading, Error] com o erro da operação',
      build: () => _controller(
        FakeAtendimentoGateway()..erroList = GrpcError.unavailable('offline'),
      ),
      act: (c) => c.carregarFila(),
      expect: () => [
        isA<LoadingState<KanbanViewModel>>(),
        isA<ErrorState<KanbanViewModel>>().having(
          (s) => s.error,
          'erro',
          isA<ListAtendimentosIndisponivel>(),
        ),
      ],
    );

    blocTest<KanbanController, ViewState<KanbanViewModel>>(
      'fila vazia é sucesso, não erro',
      build: () => _controller(FakeAtendimentoGateway()),
      act: (c) => c.carregarFila(),
      expect: () => [
        isA<LoadingState<KanbanViewModel>>(),
        isA<SuccessState<KanbanViewModel>>(),
      ],
    );
  });

  group('moverCard', () {
    test('sucesso move o card da coluna de origem para a de destino', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);
      await controller.carregarFila();

      final erro = await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 20,
      );

      expect(erro, isNull);
      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.porEtapa[10], isEmpty);
      expect(estado.data.porEtapa[20]?.single.id, 1);
      await controller.close();
    });

    test('RBAC de fluxo negado reverte o movimento otimista', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      )..erroMove = GrpcError.permissionDenied('flow_permissions');
      final controller = _controller(gateway);
      await controller.carregarFila();

      final erro = await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 20,
      );

      expect(erro, isA<MoveEtapaAcessoNegado>());
      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.porEtapa[10]?.single.id, 1, reason: 'voltou à origem');
      expect(estado.data.porEtapa[20], isEmpty);
      await controller.close();
    });

    test('transição inválida também reverte, com erro de validação', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      )..erroMove = GrpcError.failedPrecondition('etapa nao sucessora');
      final controller = _controller(gateway);
      await controller.carregarFila();

      final erro = await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 20,
      );

      expect(erro, isA<MoveEtapaMovimentoInvalido>());
      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.porEtapa[10]?.single.id, 1);
      await controller.close();
    });

    test('sem estado carregado, mover é no-op', () async {
      final controller = _controller(FakeAtendimentoGateway());

      final erro = await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 20,
      );

      expect(erro, isNull);
      expect(controller.state, isA<InitialState<KanbanViewModel>>());
      await controller.close();
    });

    test('card inexistente na coluna de origem é no-op', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);
      await controller.carregarFila();

      final erro = await controller.moverCard(
        atendimentoId: 999,
        etapaOrigemId: 10,
        etapaDestinoId: 20,
      );

      expect(erro, isNull);
      expect(gateway.chamadasMove, 0, reason: 'nem chega ao servidor');
      await controller.close();
    });
  });

  group('stream realtime', () {
    test('evento recarrega a fila depois do debounce', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway, comStream: true);
      await controller.carregarFila();
      final antes = gateway.chamadasList;

      gateway.eventos.add(
        const AtendimentoEvento(
          tipo: 'kanban.movido',
          tenantId: 'tenant-1',
          payload: {'atendimento_id': 1},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(gateway.chamadasList, greaterThan(antes));
      await controller.close();
    });

    test('rajada de eventos vira um único recarregamento', () async {
      // É para isso que o debounce existe: cinco eventos em sequência não podem
      // virar cinco RPCs.
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway, comStream: true);
      await controller.carregarFila();
      final antes = gateway.chamadasList;

      for (var i = 0; i < 5; i++) {
        gateway.eventos.add(
          const AtendimentoEvento(
            tipo: 'mensagem.recebida',
            tenantId: 'tenant-1',
            payload: {},
          ),
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(gateway.chamadasList - antes, 1);
      await controller.close();
    });

    test('erro no stream não altera o estado carregado', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway, comStream: true);
      await controller.carregarFila();
      final estadoAntes = controller.state;

      gateway.eventos.addError(GrpcError.unavailable('stream caiu'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(controller.state, same(estadoAntes));
      await controller.close();
    });

    test('sem fonte de eventos o controller funciona igual', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);

      await controller.carregarFila();

      expect(controller.state, isA<SuccessState<KanbanViewModel>>());
      await controller.close();
    });
  });

  group('recarregarAposEvento', () {
    test('preserva o departamento filtrado', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);
      await controller.carregarFila(departamentoId: 7);

      await controller.recarregarAposEvento();

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.departamentoId, 7);
      await controller.close();
    });
  });
}
