import 'package:api_client/api_client.dart' show GrpcError;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/quadro.dart';
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
  // Todo controller de teste comeca com um quadro montado: e o estado normal
  // de quem opera, e sem colunas o arrasto nao teria destino.
  gateway.colunas = gateway.colunas.isEmpty ? colunasDeTeste() : gateway.colunas;
  gateway.fluxos = gateway.fluxos.isEmpty ? fluxosDeTeste() : gateway.fluxos;
  final u = usecasesSobre(gateway);
  return KanbanController(
    listUsecase: u.list,
    moveUsecase: u.move,
    fluxosUsecase: u.fluxos,
    colunasUsecase: u.colunas,
    statusUsecase: u.status,
    eventos: comStream ? u.eventos : null,
  );
}

void main() {
  group('carregar', () {
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
      act: (c) => c.carregar(),
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
      act: (c) => c.carregar(),
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
      act: (c) => c.carregar(),
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
      await controller.carregar();

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
      await controller.carregar();

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
      await controller.carregar();

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
      await controller.carregar();

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
      await controller.carregar();
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
      await controller.carregar();
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
      await controller.carregar();
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

      await controller.carregar();

      expect(controller.state, isA<SuccessState<KanbanViewModel>>());
      await controller.close();
    });
  });

  group('colunas do quadro', () {
    test('as colunas vem do fluxo, nao dos atendimentos', () async {
      // O defeito que isto cobre: derivar as colunas dos dados fazia uma coluna
      // vazia sumir (nao havia para onde arrastar) e um quadro sem conversa
      // nenhuma abrir em branco, como se estivesse quebrado.
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      await controller.carregar();

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.colunas, hasLength(3));
      expect(estado.data.temQuadro, isTrue);
      await controller.close();
    });

    test('sem fluxo cadastrado, o quadro se declara vazio', () async {
      final gateway = FakeAtendimentoGateway()
        ..colunas = const []
        ..fluxos = const [];
      final u = usecasesSobre(gateway);
      final controller = KanbanController(
        listUsecase: u.list,
        moveUsecase: u.move,
        fluxosUsecase: u.fluxos,
        colunasUsecase: u.colunas,
        statusUsecase: u.status,
      );

      await controller.carregar();

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.temQuadro, isFalse);
      await controller.close();
    });

    test('conversa fora das colunas conhecidas nao desaparece', () async {
      // Chegou antes do fluxo existir, ou aponta para coluna ja removida.
      // Esconde-la faria sumir atendimento de verdade.
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 999)],
      );
      final controller = _controller(gateway);

      await controller.carregar();

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.semColuna.single.id, 1);
      await controller.close();
    });

    test('a lista de fluxos e buscada uma vez so', () async {
      // Configuracao muda raramente; rebusca-la a cada recarga triplicaria as
      // idas ao servidor durante uma rajada de mensagens.
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      await controller.carregar();
      await controller.carregar();
      await controller.recarregarAposEvento();

      expect(gateway.chamadasList, 3, reason: 'a fila sim, a cada vez');
      await controller.close();
    });
  });

  group('status segue a coluna', () {
    test('mover para finalizacao ja marca o cartao como resolvido', () async {
      // Sem isto, o cartao apareceria na coluna de finalizacao ainda marcado
      // como "na fila" ate a proxima recarga.
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);
      await controller.carregar();

      await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 30,
      );

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.porEtapa[30]?.single.status, 'resolvido');
      await controller.close();
    });

    test('coluna desconhecida nao inventa estado', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);
      await controller.carregar();

      await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 777,
      );

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.porEtapa[777]?.single.status, 'fila');
      await controller.close();
    });
  });

  group('definirStatus', () {
    test('repassa o status e recarrega o quadro', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      );
      final controller = _controller(gateway);
      await controller.carregar();
      final antes = gateway.chamadasList;

      final erro = await controller.definirStatus(
        atendimentoId: 1,
        status: 'resolvido',
      );

      expect(erro, isNull);
      expect(gateway.statusRecebido, 'resolvido');
      expect(gateway.chamadasList, greaterThan(antes));
      await controller.close();
    });

    test('recusa do servidor volta como erro, sem recarregar', () async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      )..erroStatus = GrpcError.permissionDenied('flow_permissions');
      final controller = _controller(gateway);
      await controller.carregar();
      final antes = gateway.chamadasList;

      final erro = await controller.definirStatus(
        atendimentoId: 1,
        status: 'resolvido',
      );

      expect(erro, isA<SetStatusAcessoNegado>());
      expect(gateway.chamadasList, antes);
      await controller.close();
    });
  });
  group('desfecho da finalizacao', () {
    test('o nome da coluna decide entre resolver e cancelar', () {
      // Um fluxo nasce com "Resolvido" e "Cancelado", ambas de finalizacao.
      // Trata-las igual faria o cartao aparecer como resolvido no instante em
      // que alguem o cancelou.
      const resolvido = ColunaDoQuadro(
        id: 1,
        nome: 'Resolvido',
        cor: '#66CDAA',
        ordem: 4,
        tipo: 'finalizacao',
      );
      const cancelado = ColunaDoQuadro(
        id: 2,
        nome: 'Cancelado',
        cor: '#FA8072',
        ordem: 5,
        tipo: 'finalizacao',
      );

      expect(resolvido.statusResultante, 'resolvido');
      expect(cancelado.statusResultante, 'cancelado');
    });

    test('aceita as variacoes que o tenant escreve', () {
      for (final nome in ['Cancelamento', 'cancelados', 'CANCELADO']) {
        final coluna = ColunaDoQuadro(
          id: 1,
          nome: nome,
          cor: '#000000',
          ordem: 1,
          tipo: 'finalizacao',
        );
        expect(coluna.statusResultante, 'cancelado', reason: nome);
      }
    });

    test('arquivar tambem tem desfecho proprio', () {
      const coluna = ColunaDoQuadro(
        id: 1,
        nome: 'Arquivado',
        cor: '#000000',
        ordem: 1,
        tipo: 'finalizacao',
      );
      expect(coluna.statusResultante, 'arquivado');
    });

    testWidgets('arrastar para "Cancelado" marca o cartao como cancelado', (
      tester,
    ) async {
      final gateway = FakeAtendimentoGateway(
        fila: [atendimentoDeTeste(id: 1, etapaAtualId: 10)],
      )..colunas = const [
          ColunaDoQuadro(
            id: 10,
            nome: 'Fila de Atendimento',
            cor: '#B0C4DE',
            ordem: 1,
            tipo: 'fila',
          ),
          ColunaDoQuadro(
            id: 40,
            nome: 'Cancelado',
            cor: '#FA8072',
            ordem: 5,
            tipo: 'finalizacao',
          ),
        ];
      final controller = _controller(gateway);
      await controller.carregar();

      await controller.moverCard(
        atendimentoId: 1,
        etapaOrigemId: 10,
        etapaDestinoId: 40,
      );

      final estado = controller.state as SuccessState<KanbanViewModel>;
      expect(estado.data.porEtapa[40]?.single.status, 'cancelado');
      await controller.close();
    });
  });
}
