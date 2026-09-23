import 'package:api_client/api_client.dart' show GrpcError;
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/chat_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/chat_state.dart';
import 'package:presentation_module/presentation_module.dart';

import '../../support/fake_gateway.dart';

ChatController _controller(FakeAtendimentoGateway gateway) {
  final u = usecasesSobre(gateway);
  return ChatController(
    getThreadUsecase: u.thread,
    sendUsecase: u.send,
    eventos: u.eventos,
    marcarLidoUsecase: u.marcarLido,
    presencaUsecase: u.presenca,
  );
}

void main() {
  group('marcarComoLida (B6)', () {
    test(
      'marca a leitura uma vez; sem mensagem nova, não volta ao servidor',
      () async {
        final gateway = FakeAtendimentoGateway(
          thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
        );
        final controller = _controller(gateway);
        await controller.abrir(5);

        await controller.marcarComoLida();
        await controller.marcarComoLida();

        expect(gateway.lidosMarcados, [5]);
        await controller.close();
      },
    );

    test('conversa só com atendente e bot não tem o que marcar', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [
          mensagemDeTeste(
            id: 1,
            timestamp: DateTime(2026, 1, 1),
            remetente: 'atendente',
          ),
          mensagemDeTeste(
            id: 2,
            timestamp: DateTime(2026, 1, 1),
            remetente: 'bot',
          ),
        ],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);

      await controller.marcarComoLida();

      expect(gateway.lidosMarcados, isEmpty);
      await controller.close();
    });

    test('sem usecase, abrir e rolar não quebram', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final u = usecasesSobre(gateway);
      final controller = ChatController(
        getThreadUsecase: u.thread,
        sendUsecase: u.send,
        eventos: u.eventos,
      );
      await controller.abrir(5);
      await controller.marcarComoLida();
      expect(gateway.lidosMarcados, isEmpty);
      await controller.close();
    });
  });

  group('abrir', () {
    blocTest<ChatController, ViewState<ChatViewModel>>(
      'carrega o histórico e sinaliza "conectando" ao abrir o stream',
      build: () => _controller(
        FakeAtendimentoGateway(
          thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
        ),
      ),
      act: (c) => c.abrir(1),
      expect: () => [
        isA<LoadingState<ChatViewModel>>(),
        isA<SuccessState<ChatViewModel>>().having(
          (s) => s.data.mensagens.length,
          'mensagens',
          1,
        ),
        isA<SuccessState<ChatViewModel>>().having(
          (s) => s.data.connectionStatus,
          'connectionStatus',
          ChatConnectionStatus.conectando,
        ),
      ],
    );

    blocTest<ChatController, ViewState<ChatViewModel>>(
      'erro do backend emite [Loading, Error] com o erro da operação',
      build: () => _controller(
        FakeAtendimentoGateway()..erroThread = GrpcError.unavailable('offline'),
      ),
      act: (c) => c.abrir(1),
      expect: () => [
        isA<LoadingState<ChatViewModel>>(),
        isA<ErrorState<ChatViewModel>>().having(
          (s) => s.error,
          'erro',
          isA<GetThreadIndisponivel>(),
        ),
      ],
    );

    blocTest<ChatController, ViewState<ChatViewModel>>(
      'atendimento inexistente chega como não encontrado',
      build: () => _controller(
        FakeAtendimentoGateway()..erroThread = GrpcError.notFound('sem'),
      ),
      act: (c) => c.abrir(99),
      expect: () => [
        isA<LoadingState<ChatViewModel>>(),
        isA<ErrorState<ChatViewModel>>().having(
          (s) => s.error,
          'erro',
          isA<GetThreadNaoEncontrado>(),
        ),
      ],
    );
  });

  group('enviar', () {
    test('sucesso recarrega o thread e não devolve erro', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(1);
      final leiturasAntes = gateway.chamadasThread;

      final erro = await controller.enviar('nova mensagem');

      expect(erro, isNull);
      expect(gateway.chamadasSend, 1);
      expect(gateway.chamadasThread, greaterThan(leiturasAntes));
      await controller.close();
    });

    test('erro devolve o caso concreto sem recarregar o thread', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      )..erroSend = GrpcError.invalidArgument('conteudo vazio');
      final controller = _controller(gateway);
      await controller.abrir(1);
      final leiturasAntes = gateway.chamadasThread;

      final erro = await controller.enviar('');

      expect(erro, isA<SendMessageConteudoInvalido>());
      expect(gateway.chamadasThread, leiturasAntes);
      await controller.close();
    });

    test('sem chat aberto, enviar é no-op', () async {
      final gateway = FakeAtendimentoGateway();
      final controller = _controller(gateway);

      final erro = await controller.enviar('ola');

      expect(erro, isNull);
      expect(gateway.chamadasSend, 0);
      await controller.close();
    });
  });

  group('stream realtime', () {
    test('queda muda o status para reconectando sem perder o thread', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(1);

      gateway.eventos.addError(GrpcError.unavailable('conexao caiu'));
      await Future<void>.delayed(Duration.zero);

      final estado = controller.state as SuccessState<ChatViewModel>;
      expect(estado.data.connectionStatus, ChatConnectionStatus.reconectando);
      expect(
        estado.data.mensagens,
        hasLength(1),
        reason: 'só o indicador de conexão muda',
      );
      await controller.close();
    });

    test(
      'evento do atendimento aberto recarrega o thread e marca conectado',
      () async {
        final gateway = FakeAtendimentoGateway(
          thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
        );
        final controller = _controller(gateway);
        await controller.abrir(7);
        final leiturasAntes = gateway.chamadasThread;

        gateway.eventos.add(
          const AtendimentoEvento(
            tipo: 'mensagem.recebida',
            tenantId: 'tenant-1',
            payload: {'atendimento_id': 7},
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(gateway.chamadasThread, greaterThan(leiturasAntes));
        final estado = controller.state as SuccessState<ChatViewModel>;
        expect(estado.data.connectionStatus, ChatConnectionStatus.conectado);
        await controller.close();
      },
    );

    test('evento de outro atendimento não recarrega o thread', () async {
      // Evita I/O desnecessário quando a fila é movimentada por outro atendente.
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(7);
      final leiturasAntes = gateway.chamadasThread;

      gateway.eventos.add(
        const AtendimentoEvento(
          tipo: 'mensagem.recebida',
          tenantId: 'tenant-1',
          payload: {'atendimento_id': 999},
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gateway.chamadasThread, leiturasAntes);
      await controller.close();
    });

    test('close encerra a assinatura e cancela a reconexão pendente', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(1);
      gateway.eventos.addError(GrpcError.unavailable('caiu'));
      await Future<void>.delayed(Duration.zero);

      await controller.close();

      // Sem exceção de "emit after close": o timer de backoff foi cancelado.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(controller.isClosed, isTrue);
    });
  });
  // ─── P2: histórico para trás e citação ───────────────────────────────────
  group('conversa fiel (P2)', () {
    test('rolar para o topo carrega o trecho anterior e o mantém', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [
          mensagemDeTeste(id: 10, timestamp: DateTime(2026, 1, 2)),
          mensagemDeTeste(id: 11, timestamp: DateTime(2026, 1, 2, 1)),
        ],
      )..anteriores = [
        mensagemDeTeste(id: 8, timestamp: DateTime(2026, 1, 1)),
        mensagemDeTeste(id: 9, timestamp: DateTime(2026, 1, 1, 1)),
      ];
      final controller = _controller(gateway);
      await controller.abrir(5);

      await controller.carregarAntigas();

      // O cursor é o id da bolha mais antiga que estava na tela.
      expect(gateway.ultimoBeforeId, 10);
      final vm = (controller.state as SuccessState<ChatViewModel>).data;
      expect(vm.mensagens.map((m) => m.id), [8, 9, 10, 11]);
      expect(vm.carregandoAntigas, isFalse);
      await controller.close();
    });

    test('página vazia marca o fim do histórico e não pede de novo', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 10, timestamp: DateTime(2026, 1, 2))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);
      final antes = gateway.chamadasThread;

      await controller.carregarAntigas();
      await controller.carregarAntigas();

      expect(gateway.chamadasThread, antes + 1);
      final vm = (controller.state as SuccessState<ChatViewModel>).data;
      expect(vm.fimDoHistorico, isTrue);
      await controller.close();
    });

    test('citar acompanha o envio e some depois dele', () async {
      final citada = mensagemDeTeste(id: 7, timestamp: DateTime(2026, 1, 1));
      final gateway = FakeAtendimentoGateway(thread: [citada]);
      final controller = _controller(gateway);
      await controller.abrir(5);

      controller.citar(citada);
      expect(
        (controller.state as SuccessState<ChatViewModel>).data.citando?.id,
        7,
      );

      await controller.enviar('respondendo');

      expect(gateway.ultimaCitacaoEnviada, 7);
      // A citação vale para uma resposta só.
      expect(
        (controller.state as SuccessState<ChatViewModel>).data.citando,
        isNull,
      );
      await controller.close();
    });

    test('a recarga do envio não apaga o histórico já puxado', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 10, timestamp: DateTime(2026, 1, 2))],
      )..anteriores = [mensagemDeTeste(id: 9, timestamp: DateTime(2026, 1, 1))];
      final controller = _controller(gateway);
      await controller.abrir(5);
      await controller.carregarAntigas();

      await controller.enviar('oi');

      final vm = (controller.state as SuccessState<ChatViewModel>).data;
      expect(vm.mensagens.map((m) => m.id), containsAll([9, 10]));
      await controller.close();
    });
  });
  // ─── P3: presença ─────────────────────────────────────────────────────────
  group('presença (P3)', () {
    test('digitar avisa uma vez só dentro da janela de renovação', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);

      await controller.avisarQueEstaDigitando();
      await controller.avisarQueEstaDigitando();
      await controller.avisarQueEstaDigitando();

      // Uma chamada por pausa, não uma por tecla.
      expect(gateway.presencasEnviadas, ['composing']);
      await controller.close();
    });

    test('gravar áudio avisa "recording" mesmo dentro da janela', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);

      await controller.avisarQueEstaDigitando();
      await controller.avisarQueEstaDigitando(gravandoAudio: true);

      expect(gateway.presencasEnviadas, ['composing', 'recording']);
      await controller.close();
    });

    test('enviar encerra a digitação', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);
      await controller.avisarQueEstaDigitando();

      await controller.enviar('pronto');
      await Future<void>.delayed(Duration.zero);

      expect(gateway.presencasEnviadas, ['composing', 'paused']);
      await controller.close();
    });

    test('a presença do contato aparece e não recarrega a conversa', () async {
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);
      final recargas = gateway.chamadasThread;

      gateway.eventos.add(
        const AtendimentoEvento(
          tipo: 'whatsapp.presenca',
          tenantId: 't',
          payload: {'atendimento_id': 5, 'situacao': 'composing'},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final vm = (controller.state as SuccessState<ChatViewModel>).data;
      expect(vm.presencaDoContato, 'composing');
      expect(gateway.chamadasThread, recargas);
      await controller.close();
    });

    test('campos da IA avisam a ficha sem recarregar a conversa', () async {
      // P10 — a v1 publicava `custom_field.updated` e a ficha aberta se
      // atualizava. Recarregar o thread por isso seria I/O à toa.
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);
      final recargas = gateway.chamadasThread;

      gateway.eventos
        ..add(
          const AtendimentoEvento(
            tipo: 'atendimento.campos_atualizados',
            tenantId: 't',
            payload: {'atendimento_id': 5, 'gravados': 2},
          ),
        )
        // De outra conversa: não é desta ficha.
        ..add(
          const AtendimentoEvento(
            tipo: 'atendimento.campos_atualizados',
            tenantId: 't',
            payload: {'atendimento_id': 99, 'gravados': 1},
          ),
        );
      await Future<void>.delayed(Duration.zero);

      expect(controller.camposAtualizados.value, 1);
      expect(gateway.chamadasThread, recargas);
      await controller.close();
    });

    test('etiqueta posta pela IA também avisa a ficha', () async {
      // P14 — a etiqueta da intenção muda a ficha, não a conversa.
      final gateway = FakeAtendimentoGateway(
        thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
      );
      final controller = _controller(gateway);
      await controller.abrir(5);
      final recargas = gateway.chamadasThread;

      gateway.eventos.add(
        const AtendimentoEvento(
          tipo: 'atendimento.etiquetas_atualizadas',
          tenantId: 't',
          payload: {'atendimento_id': 5},
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(controller.camposAtualizados.value, 1);
      expect(gateway.chamadasThread, recargas);
      await controller.close();
    });
  });
}
