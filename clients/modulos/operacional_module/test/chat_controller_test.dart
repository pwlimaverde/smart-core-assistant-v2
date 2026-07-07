import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/services/atendimento_service.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/get_thread_usecase.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/send_outbound_message_usecase.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/chat_controller.dart';
import 'package:operacional_module/src/features/atendimento/presentation/controllers/chat_state.dart';
import 'package:presentation_module/presentation_module.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Fake do [AtendimentoService]: thread fixo + stream controlável pelo teste
/// (nunca abre rede/gRPC real).
class _FakeAtendimentoService implements AtendimentoService {
  ReturnSuccessOrError<List<MensagemThread>> threadResult;
  ReturnSuccessOrError<int> sendResult;
  final StreamController<AtendimentoEvento> streamController;

  _FakeAtendimentoService({
    required this.threadResult,
    this.sendResult = const SuccessReturn(success: 1),
    StreamController<AtendimentoEvento>? streamController,
  }) : streamController = streamController ?? StreamController.broadcast();

  @override
  Future<ReturnSuccessOrError<List<MensagemThread>>> getThread({
    required int atendimentoId,
    int limit = 50,
    int offset = 0,
  }) async => threadResult;

  @override
  Future<ReturnSuccessOrError<int>> sendOutboundMessage({
    required int atendimentoId,
    required String conteudo,
    String tipo = 'texto',
  }) async => sendResult;

  @override
  Future<ReturnSuccessOrError<List<AtendimentoResumo>>> listAtendimentos({
    String status = 'fila',
    int? departamentoId,
    int limit = 50,
  }) async => const SuccessReturn(success: []);

  @override
  Future<ReturnSuccessOrError<Unit>> moveAtendimentoEtapa({
    required int atendimentoId,
    required int etapaDestinoId,
    String motivo = '',
  }) async => const SuccessReturn(success: unit);

  @override
  Stream<AtendimentoEvento> streamAtendimentos() => streamController.stream;
}

MensagemThread _mensagem(int id) => MensagemThread(
  id: id,
  atendimentoId: 1,
  tipo: 'texto',
  conteudo: 'Olá $id',
  remetente: 'usuario',
  timestamp: DateTime(2026, 1, 1),
  statusEnvio: 'enviado',
);

void main() {
  group('ChatController.abrir', () {
    blocTest<ChatController, ViewState<ChatViewModel>>(
      'carrega o histórico e emite [Loading, Success (thread), Success (status conectando)]',
      build: () {
        final service = _FakeAtendimentoService(
          threadResult: SuccessReturn(success: [_mensagem(1)]),
        );
        return ChatController(
          getThreadUsecase: GetThreadUsecase(service: service),
          sendUsecase: SendOutboundMessageUsecase(service: service),
          service: service,
        );
      },
      act: (c) => c.abrir(1),
      // 1) Loading; 2) Success com o thread carregado; 3) Success com o status
      // de conexão atualizado para "conectando" ao abrir o stream realtime.
      expect: () => [
        isA<LoadingState<ChatViewModel>>(),
        isA<SuccessState<ChatViewModel>>()
            .having((s) => s.data.mensagens.length, 'mensagens', 1),
        isA<SuccessState<ChatViewModel>>().having(
          (s) => s.data.connectionStatus,
          'connectionStatus',
          ChatConnectionStatus.conectando,
        ),
      ],
    );

    blocTest<ChatController, ViewState<ChatViewModel>>(
      'erro do backend: emite [Loading, Error]',
      build: () {
        final service = _FakeAtendimentoService(
          threadResult: const ErrorReturn(error: ErrorNetwork()),
        );
        return ChatController(
          getThreadUsecase: GetThreadUsecase(service: service),
          sendUsecase: SendOutboundMessageUsecase(service: service),
          service: service,
        );
      },
      act: (c) => c.abrir(1),
      expect: () => [
        isA<LoadingState<ChatViewModel>>(),
        isA<ErrorState<ChatViewModel>>(),
      ],
    );
  });

  group('ChatController.enviar', () {
    test('sucesso: recarrega o thread e não retorna erro', () async {
      final service = _FakeAtendimentoService(
        threadResult: SuccessReturn(success: [_mensagem(1)]),
      );
      final controller = ChatController(
        getThreadUsecase: GetThreadUsecase(service: service),
        sendUsecase: SendOutboundMessageUsecase(service: service),
        service: service,
      );
      await controller.abrir(1);

      final erro = await controller.enviar('nova mensagem');

      expect(erro, isNull);
      await controller.close();
    });

    test('erro do backend: devolve o AppError sem recarregar', () async {
      final service = _FakeAtendimentoService(
        threadResult: SuccessReturn(success: [_mensagem(1)]),
        sendResult: const ErrorReturn(error: ErrorValidation()),
      );
      final controller = ChatController(
        getThreadUsecase: GetThreadUsecase(service: service),
        sendUsecase: SendOutboundMessageUsecase(service: service),
        service: service,
      );
      await controller.abrir(1);

      final erro = await controller.enviar('');

      expect(erro, isA<ErrorValidation>());
      await controller.close();
    });
  });
}
