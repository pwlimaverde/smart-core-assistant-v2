import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/services/atendimento_service.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/list_atendimentos_usecase.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/move_atendimento_etapa_usecase.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/kanban_state.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Fake do [AtendimentoService] parametrizável por teste — evita subir
/// gRPC/rede: só exercita a orquestração de estado do controller.
class _FakeAtendimentoService implements AtendimentoService {
  ReturnSuccessOrError<List<AtendimentoResumo>> listResult;
  ReturnSuccessOrError<Unit> moveResult;
  final StreamController<AtendimentoEvento> streamController;
  int listCalls = 0;

  _FakeAtendimentoService({
    required this.listResult,
    this.moveResult = const SuccessReturn(success: unit),
    StreamController<AtendimentoEvento>? streamController,
  }) : streamController = streamController ?? StreamController.broadcast();

  @override
  Future<ReturnSuccessOrError<List<AtendimentoResumo>>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async {
    listCalls++;
    return listResult;
  }

  @override
  Future<ReturnSuccessOrError<Unit>> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async => moveResult;

  @override
  Future<ReturnSuccessOrError<List<MensagemThread>>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async => const SuccessReturn(success: []);

  @override
  Future<ReturnSuccessOrError<int>> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async => const SuccessReturn(success: 1);

  @override
  Stream<AtendimentoEvento> streamAtendimentos() => streamController.stream;
}

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
  group('KanbanController.carregarFila', () {
    blocTest<KanbanController, ViewState<KanbanViewModel>>(
      'sucesso: emite [Loading, Success] com atendimentos agrupados por etapa',
      build: () {
        final service = _FakeAtendimentoService(
          listResult: SuccessReturn(
            success: [
              _atendimento(id: 1, etapaAtualId: 10),
              _atendimento(id: 2, etapaAtualId: 20),
            ],
          ),
        );
        return KanbanController(
          listUsecase: ListAtendimentosUsecase(service: service),
          moveUsecase: MoveAtendimentoEtapaUsecase(service: service),
        );
      },
      act: (c) => c.carregarFila(),
      expect: () => [
        isA<LoadingState<KanbanViewModel>>(),
        isA<SuccessState<KanbanViewModel>>()
            .having((s) => s.data.porEtapa.keys, 'etapas', containsAll([10, 20])),
      ],
    );

    blocTest<KanbanController, ViewState<KanbanViewModel>>(
      'erro do backend: emite [Loading, Error]',
      build: () {
        final service = _FakeAtendimentoService(
          listResult: const ErrorReturn(error: ErrorNetwork()),
        );
        return KanbanController(
          listUsecase: ListAtendimentosUsecase(service: service),
          moveUsecase: MoveAtendimentoEtapaUsecase(service: service),
        );
      },
      act: (c) => c.carregarFila(),
      expect: () => [
        isA<LoadingState<KanbanViewModel>>(),
        isA<ErrorState<KanbanViewModel>>(),
      ],
    );
  });

  group('KanbanController.moverCard', () {
    test('sucesso: move o card da etapa de origem para a de destino', () async {
      final service = _FakeAtendimentoService(
        listResult: SuccessReturn(success: [_atendimento(id: 1, etapaAtualId: 10)]),
      );
      final controller = KanbanController(
        listUsecase: ListAtendimentosUsecase(service: service),
        moveUsecase: MoveAtendimentoEtapaUsecase(service: service),
      );
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

    test(
      'erro do backend (ex.: RBAC de fluxo negado): reverte o movimento local',
      () async {
        final service = _FakeAtendimentoService(
          listResult: SuccessReturn(success: [_atendimento(id: 1, etapaAtualId: 10)]),
          moveResult: const ErrorReturn(
            error: ErrorUnauthorized(message: 'Acesso negado.'),
          ),
        );
        final controller = KanbanController(
          listUsecase: ListAtendimentosUsecase(service: service),
          moveUsecase: MoveAtendimentoEtapaUsecase(service: service),
        );
        await controller.carregarFila();

        final erro = await controller.moverCard(
          atendimentoId: 1,
          etapaOrigemId: 10,
          etapaDestinoId: 20,
        );

        expect(erro, isA<ErrorUnauthorized>());
        final estado = controller.state as SuccessState<KanbanViewModel>;
        // Revertido: o card volta para a coluna de origem.
        expect(estado.data.porEtapa[10]?.single.id, 1);
        expect(estado.data.porEtapa[20], isEmpty);
        await controller.close();
      },
    );
  });

  group('KanbanController — stream realtime', () {
    test(
      'evento no stream recarrega a fila (debounced) via recarregarAposEvento',
      () async {
        final service = _FakeAtendimentoService(
          listResult: SuccessReturn(success: [_atendimento(id: 1, etapaAtualId: 10)]),
        );
        final controller = KanbanController(
          service: service,
          listUsecase: ListAtendimentosUsecase(service: service),
          moveUsecase: MoveAtendimentoEtapaUsecase(service: service),
        );
        await controller.carregarFila();
        final chamadasAntes = service.listCalls;

        service.streamController.add(
          const AtendimentoEvento(
            tipo: 'kanban.movido',
            tenantId: 'tenant-1',
            payload: {'atendimento_id': 1},
          ),
        );
        // O debounce agrupa rajadas em 400ms antes de recarregar.
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(service.listCalls, greaterThan(chamadasAntes));
        await controller.close();
      },
    );

    test(
      'erro no stream realtime não derruba nem altera o estado já carregado',
      () async {
        final service = _FakeAtendimentoService(
          listResult: SuccessReturn(success: [_atendimento(id: 1, etapaAtualId: 10)]),
        );
        final controller = KanbanController(
          service: service,
          listUsecase: ListAtendimentosUsecase(service: service),
          moveUsecase: MoveAtendimentoEtapaUsecase(service: service),
        );
        await controller.carregarFila();
        final estadoAntes = controller.state;

        service.streamController.addError(Exception('conexão instável'));
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(controller.state, same(estadoAntes));
        await controller.close();
      },
    );
  });
}
