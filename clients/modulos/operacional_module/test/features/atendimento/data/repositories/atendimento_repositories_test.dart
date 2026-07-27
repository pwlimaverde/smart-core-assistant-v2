import 'package:api_client/api_client.dart' show GrpcError;
import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/gateways/atendimento_gateway.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/get_thread_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/list_atendimentos_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/move_atendimento_etapa_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/send_outbound_message_parameters.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../../support/fake_gateway.dart';

void main() {
  const listParams = ListAtendimentosParameters();
  const threadParams = GetThreadParameters(atendimentoId: 7);
  const moveParams = MoveAtendimentoEtapaParameters(
    atendimentoId: 7,
    etapaDestinoId: 20,
  );
  const sendParams = SendOutboundMessageParameters(
    atendimentoId: 7,
    conteudo: 'mensagem do atendente',
  );

  /// Erro do motor local, como o gateway do desktop o entrega.
  final falhaLocal = const LocalEngineFalha(
    'falha no motor local: database is locked',
    'database is locked',
  );

  group('ListAtendimentosRepository', () {
    test('sucesso devolve a fila', () async {
      final gateway = FakeAtendimentoGateway(fila: [atendimentoDeTeste(id: 1)]);

      final r = await usecasesSobre(gateway).list(listParams);

      expect((r as Success).value, hasLength(1));
    });

    test(
      'permissão negada vira acesso negado (marcado como não autorizado)',
      () async {
        final gateway = FakeAtendimentoGateway()
          ..erroList = GrpcError.permissionDenied('sem escopo');

        final erro =
            ((await usecasesSobre(gateway).list(listParams)) as Failure).error;

        expect(erro, isA<ListAtendimentosAcessoNegado>());
        expect(erro, isA<UnauthorizedFailure>());
      },
    );

    test('servidor indisponível é falha de rede', () async {
      final gateway = FakeAtendimentoGateway()
        ..erroList = GrpcError.unavailable('offline');

      final erro =
          ((await usecasesSobre(gateway).list(listParams)) as Failure).error;

      expect(erro, isA<ListAtendimentosIndisponivel>());
      expect(erro, isA<NetworkFailure>());
    });

    test('falha do motor local NÃO é confundida com falha de rede', () async {
      // No desktop a leitura vem do índice SQLite: "tente novamente" não resolve.
      final gateway = FakeAtendimentoGateway()..erroList = falhaLocal;

      final erro =
          ((await usecasesSobre(gateway).list(listParams)) as Failure).error;

      expect(erro, isA<ListAtendimentosFalhaLocal>());
      expect(erro, isNot(isA<NetworkFailure>()));
      expect((erro as ListAtendimentosError).message, contains('Reinicie'));
    });

    test('exceção fora do transporte vira inesperado', () async {
      final gateway = FakeAtendimentoGateway()
        ..erroList = const FormatException('json corrompido');

      expect(
        ((await usecasesSobre(gateway).list(listParams)) as Failure).error,
        isA<ListAtendimentosInesperado>(),
      );
    });

    test('a mensagem exibida não carrega o texto da exceção', () async {
      final gateway = FakeAtendimentoGateway()
        ..erroList = GrpcError.internal(
          'stack interno: /srv/app/handler.rs:42',
        );

      final erro =
          ((await usecasesSobre(gateway).list(listParams)) as Failure).error
              as ListAtendimentosError;

      expect(erro.message, isNot(contains('handler.rs')));
    });
  });

  group('GetThreadRepository', () {
    test('atendimento inexistente vira não encontrado', () async {
      final gateway = FakeAtendimentoGateway()
        ..erroThread = GrpcError.notFound('sem atendimento');

      expect(
        ((await usecasesSobre(gateway).thread(threadParams)) as Failure).error,
        isA<GetThreadNaoEncontrado>(),
      );
    });

    test('falha do motor local tem caso próprio', () async {
      final gateway = FakeAtendimentoGateway()..erroThread = falhaLocal;

      expect(
        ((await usecasesSobre(gateway).thread(threadParams)) as Failure).error,
        isA<GetThreadFalhaLocal>(),
      );
    });

    test('sem permissão no atendimento', () async {
      final gateway = FakeAtendimentoGateway()
        ..erroThread = GrpcError.unauthenticated('sessao');

      expect(
        ((await usecasesSobre(gateway).thread(threadParams)) as Failure).error,
        isA<GetThreadAcessoNegado>(),
      );
    });
  });

  group('MoveAtendimentoEtapaRepository', () {
    test('sucesso resolve em Unit', () async {
      final gateway = FakeAtendimentoGateway();

      expect(await usecasesSobre(gateway).move(moveParams), isA<Success>());
      expect(gateway.chamadasMove, 1);
    });

    test('RBAC de fluxo negado vira acesso negado', () async {
      // O RBAC fino por fluxo é decidido no servidor; a UI só exibe.
      final gateway = FakeAtendimentoGateway()
        ..erroMove = GrpcError.permissionDenied('flow_permissions');

      final erro =
          ((await usecasesSobre(gateway).move(moveParams)) as Failure).error;

      expect(erro, isA<MoveEtapaAcessoNegado>());
    });

    test(
      'transição recusada vira movimento inválido, não erro de rede',
      () async {
        for (final falha in [
          GrpcError.failedPrecondition('etapa nao sucessora'),
          GrpcError.invalidArgument('etapa de outro fluxo'),
        ]) {
          final gateway = FakeAtendimentoGateway()..erroMove = falha;

          final erro =
              ((await usecasesSobre(gateway).move(moveParams)) as Failure)
                  .error;

          expect(erro, isA<MoveEtapaMovimentoInvalido>());
          expect(erro, isA<ValidationFailure>());
        }
      },
    );

    test('falha do motor local tem caso próprio', () async {
      final gateway = FakeAtendimentoGateway()..erroMove = falhaLocal;

      expect(
        ((await usecasesSobre(gateway).move(moveParams)) as Failure).error,
        isA<MoveEtapaFalhaLocal>(),
      );
    });
  });

  group('SendOutboundMessageRepository', () {
    test('sucesso devolve o id persistido', () async {
      final gateway = FakeAtendimentoGateway(messageId: 987);

      final r = await usecasesSobre(gateway).send(sendParams);

      expect((r as Success).value, 987);
    });

    test(
      'id negativo (mensagem pendente de sync no desktop) é sucesso',
      () async {
        // O motor local devolve id provisório negativo até o sync promover.
        final gateway = FakeAtendimentoGateway(messageId: -42);

        final r = await usecasesSobre(gateway).send(sendParams);

        expect((r as Success).value, -42);
      },
    );

    test('conteúdo recusado e estado inválido são erros distintos', () async {
      final gatewayConteudo = FakeAtendimentoGateway()
        ..erroSend = GrpcError.invalidArgument('vazio');
      final gatewayEstado = FakeAtendimentoGateway()
        ..erroSend = GrpcError.failedPrecondition('janela fechada');

      expect(
        ((await usecasesSobre(gatewayConteudo).send(sendParams)) as Failure)
            .error,
        isA<SendMessageConteudoInvalido>(),
      );
      expect(
        ((await usecasesSobre(gatewayEstado).send(sendParams)) as Failure)
            .error,
        isA<SendMessageEstadoInvalido>(),
      );
    });

    test('o conteúdo da mensagem nunca aparece na mensagem de erro', () async {
      // `conteudo` é PII: chega ao mapError como contexto, mas não pode sair dele.
      final gateway = FakeAtendimentoGateway()
        ..erroSend = GrpcError.internal('falha');

      final erro =
          ((await usecasesSobre(gateway).send(sendParams)) as Failure).error
              as SendOutboundMessageError;

      expect(erro.message, isNot(contains('mensagem do atendente')));
    });
  });
}
