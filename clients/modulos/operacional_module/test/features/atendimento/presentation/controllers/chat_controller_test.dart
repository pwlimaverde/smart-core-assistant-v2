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
  );
}

void main() {
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
}
