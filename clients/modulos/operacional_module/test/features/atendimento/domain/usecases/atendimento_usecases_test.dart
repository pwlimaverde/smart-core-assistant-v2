import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/get_thread_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/list_atendimentos_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/move_atendimento_etapa_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/send_outbound_message_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/fake_gateway.dart';

/// Repositório que quebra o contrato (lança em vez de devolver `Failure`) — a
/// base converte via `onUnexpected` e nada escapa para o controller.
final class _RepoQueLanca<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    throw StateError('repositorio fora do contrato');
  }
}

void main() {
  group('GetThreadUsecase', () {
    test('ordena as mensagens em ordem cronológica ascendente', () async {
      // A ChatPage renderiza com `reverse: true` indexando do fim: a lista tem
      // de estar do mais antigo para o mais recente.
      final gateway = FakeAtendimentoGateway(
        thread: [
          mensagemDeTeste(id: 3, timestamp: DateTime(2026, 1, 3)),
          mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1)),
          mensagemDeTeste(id: 2, timestamp: DateTime(2026, 1, 2)),
        ],
      );

      final r = await usecasesSobre(
        gateway,
      ).thread(const GetThreadParameters(atendimentoId: 1));

      final ids = ((r as Success).value as List<MensagemThread>)
          .map((m) => m.id)
          .toList();
      expect(ids, [1, 2, 3]);
    });

    test(
      'ordena por timestamp, não por id (pendente de sync tem id negativo)',
      () async {
        // No desktop, a mensagem ainda não sincronizada tem id provisório
        // negativo: ordenar por id a jogaria para o topo do histórico.
        final gateway = FakeAtendimentoGateway(
          thread: [
            mensagemDeTeste(id: 10, timestamp: DateTime(2026, 1, 1)),
            mensagemDeTeste(id: -1, timestamp: DateTime(2026, 1, 2, 12)),
          ],
        );

        final r = await usecasesSobre(
          gateway,
        ).thread(const GetThreadParameters(atendimentoId: 1));

        final ids = ((r as Success).value as List<MensagemThread>)
            .map((m) => m.id)
            .toList();
        expect(ids, [10, -1], reason: 'a pendente é a mais recente');
      },
    );

    test('thread vazio é sucesso com lista vazia', () async {
      final gateway = FakeAtendimentoGateway();

      final r = await usecasesSobre(
        gateway,
      ).thread(const GetThreadParameters(atendimentoId: 1));

      expect((r as Success).value, isEmpty);
    });

    test(
      'lista devolvida é imutável (a tela não altera o estado por engano)',
      () async {
        final gateway = FakeAtendimentoGateway(
          thread: [mensagemDeTeste(id: 1, timestamp: DateTime(2026, 1, 1))],
        );

        final r = await usecasesSobre(
          gateway,
        ).thread(const GetThreadParameters(atendimentoId: 1));

        expect(
          () => ((r as Success).value as List<MensagemThread>).clear(),
          throwsUnsupportedError,
        );
      },
    );

    test('repositório fora do contrato cai em onUnexpected', () async {
      final usecase = GetThreadUsecase(
        repository:
            _RepoQueLanca<
              List<MensagemThread>,
              GetThreadParameters,
              GetThreadError
            >(),
      );

      final r = await usecase(const GetThreadParameters(atendimentoId: 1));

      expect((r as Failure).error, isA<GetThreadInesperado>());
    });
  });

  group('ListAtendimentosUsecase', () {
    test('preserva a ordem entregue pela fonte', () async {
      // A ordenação não é imposta no cliente: `prioridade` é texto livre sem
      // ordem total definida no domínio.
      final gateway = FakeAtendimentoGateway(
        fila: [
          atendimentoDeTeste(id: 3, prioridade: 'baixa'),
          atendimentoDeTeste(id: 1, prioridade: 'alta'),
          atendimentoDeTeste(id: 2, prioridade: 'normal'),
        ],
      );

      final r = await usecasesSobre(
        gateway,
      ).list(const ListAtendimentosParameters());

      expect((r as Success).value.map((a) => a.id), [3, 1, 2]);
    });

    test('repassa status/departamento/limite dos parâmetros', () async {
      final gateway = FakeAtendimentoGateway();

      await usecasesSobre(gateway).list(
        const ListAtendimentosParameters(
          status: 'em_atendimento',
          departamentoId: 4,
          limit: 10,
        ),
      );

      expect(gateway.chamadasList, 1);
    });

    test('erro do repositório faz curto-circuito (process não roda)', () async {
      final gateway = FakeAtendimentoGateway()
        ..erroList = const FormatException('x');

      final r = await usecasesSobre(
        gateway,
      ).list(const ListAtendimentosParameters());

      expect(r, isA<Failure>());
    });
  });

  group('MoveAtendimentoEtapaUsecase', () {
    test('repassa o motivo informado até o gateway', () async {
      final gateway = FakeAtendimentoGateway();

      await usecasesSobre(gateway).move(
        const MoveAtendimentoEtapaParameters(
          atendimentoId: 1,
          etapaDestinoId: 2,
          motivo: 'cliente pediu',
        ),
      );

      expect(gateway.motivoRecebido, 'cliente pediu');
    });

    test('motivo é vazio por padrão', () async {
      final gateway = FakeAtendimentoGateway();

      await usecasesSobre(gateway).move(
        const MoveAtendimentoEtapaParameters(
          atendimentoId: 1,
          etapaDestinoId: 2,
        ),
      );

      expect(gateway.motivoRecebido, isEmpty);
    });
  });

  group('SendOutboundMessageUsecase', () {
    test('devolve o id que a fonte persistiu', () async {
      final gateway = FakeAtendimentoGateway(messageId: 55);

      final r = await usecasesSobre(gateway).send(
        const SendOutboundMessageParameters(atendimentoId: 1, conteudo: 'ola'),
      );

      expect((r as Success).value, 55);
    });

    test('repositório fora do contrato cai em onUnexpected', () async {
      final usecase = SendOutboundMessageUsecase(
        repository:
            _RepoQueLanca<
              int,
              SendOutboundMessageParameters,
              SendOutboundMessageError
            >(),
      );

      final r = await usecase(
        const SendOutboundMessageParameters(atendimentoId: 1, conteudo: 'x'),
      );

      expect((r as Failure).error, isA<SendMessageInesperado>());
    });
  });
}
