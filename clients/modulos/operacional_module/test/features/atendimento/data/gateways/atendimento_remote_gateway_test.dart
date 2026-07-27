import 'package:api_client/api_client.dart' as proto;
import 'package:api_client/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fixnum/fixnum.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operacional_module/src/features/atendimento/data/gateways/atendimento_remote_gateway.dart';

class _MockAdminClient extends Mock implements proto.AdminServiceClient {}

Int64 _ms(DateTime d) => Int64(d.millisecondsSinceEpoch);

void main() {
  late _MockAdminClient client;
  late AtendimentoRemoteGateway gateway;

  setUpAll(() {
    registerFallbackValue(proto.ListAtendimentosRequest());
    registerFallbackValue(proto.GetThreadRequest());
    registerFallbackValue(proto.MoveAtendimentoEtapaRequest());
    registerFallbackValue(proto.SendOutboundMessageRequest());
    registerFallbackValue(proto.StreamAtendimentosRequest());
  });

  setUp(() {
    client = _MockAdminClient();
    gateway = AtendimentoRemoteGateway(client: client);
  });

  group('listAtendimentos', () {
    test('repassa filtros e converte o resumo do protobuf', () async {
      when(() => client.listAtendimentos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListAtendimentosResponse(
            atendimentos: [
              proto.AtendimentoResumo(
                id: 1,
                contatoId: 2,
                status: 'fila',
                departamentoId: 3,
                fluxoAtendimentoId: 4,
                etapaAtualId: 5,
                assunto: 'Assunto',
                prioridade: 'alta',
                atendenteHumanoId: 6,
                dataInicio: _ms(DateTime(2026, 1, 1)),
                dataUltimaMensagem: _ms(DateTime(2026, 1, 2)),
              ),
            ],
          ),
        ),
      );

      final fila = await gateway.listAtendimentos(
        status: 'em_atendimento',
        departamentoId: 3,
        limit: 10,
      );

      final enviado =
          verify(() => client.listAtendimentos(captureAny())).captured.single
              as proto.ListAtendimentosRequest;
      expect(enviado.status, 'em_atendimento');
      expect(enviado.departamentoId, 3);
      expect(enviado.limit, 10);

      final a = fila.single;
      expect(a.id, 1);
      expect(a.etapaAtualId, 5);
      expect(a.prioridade, 'alta');
      expect(a.dataInicio, DateTime(2026, 1, 1));
      expect(a.dataUltimaMensagem, DateTime(2026, 1, 2));
    });

    test('campos opcionais ausentes chegam como null, não como zero', () async {
      // Convenção do protobuf: ausência é 0/vazio. Deixar o 0 passar faria a UI
      // procurar por um departamento de id 0, que não existe.
      when(() => client.listAtendimentos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListAtendimentosResponse(
            atendimentos: [
              proto.AtendimentoResumo(
                id: 1,
                contatoId: 2,
                status: 'fila',
                assunto: '',
                prioridade: 'normal',
                dataInicio: _ms(DateTime(2026, 1, 1)),
              ),
            ],
          ),
        ),
      );

      final a = (await gateway.listAtendimentos()).single;

      expect(a.departamentoId, isNull);
      expect(a.fluxoAtendimentoId, isNull);
      expect(a.etapaAtualId, isNull);
      expect(a.atendenteHumanoId, isNull);
      expect(a.dataUltimaMensagem, isNull);
      expect(a.sentimentoNota, isNull);
      expect(a.sentimentoLabel, isNull);
    });

    test('sem departamento no filtro envia 0 (todos)', () async {
      when(
        () => client.listAtendimentos(any()),
      ).thenAnswer((_) => respostaGrpc(proto.ListAtendimentosResponse()));

      await gateway.listAtendimentos();

      final enviado =
          verify(() => client.listAtendimentos(captureAny())).captured.single
              as proto.ListAtendimentosRequest;
      expect(enviado.departamentoId, 0);
    });

    test('sentimento da IA é preservado quando presente', () async {
      when(() => client.listAtendimentos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListAtendimentosResponse(
            atendimentos: [
              proto.AtendimentoResumo(
                id: 1,
                contatoId: 2,
                status: 'fila',
                assunto: '',
                prioridade: 'normal',
                dataInicio: _ms(DateTime(2026, 1, 1)),
                sentimentoNota: -2,
                sentimentoLabel: 'negativo',
              ),
            ],
          ),
        ),
      );

      final a = (await gateway.listAtendimentos()).single;

      expect(a.sentimentoNota, -2);
      expect(a.sentimentoLabel, 'negativo');
    });

    test('falha do transporte sobe crua', () async {
      when(() => client.listAtendimentos(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.permissionDenied('sem escopo')),
      );

      await expectLater(
        gateway.listAtendimentos(),
        throwsA(isA<proto.GrpcError>()),
      );
    });
  });

  group('getThread', () {
    test('converte as mensagens e repassa paginação', () async {
      when(() => client.getThread(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetThreadResponse(
            mensagens: [
              proto.MensagemThread(
                id: 10,
                atendimentoId: 7,
                tipo: 'texto',
                conteudo: 'ola',
                remetente: 'cliente',
                timestamp: _ms(DateTime(2026, 1, 1, 10)),
                statusEnvio: 'entregue',
                geradoPorIa: true,
                resumoMidia: 'foto de um documento',
              ),
            ],
          ),
        ),
      );

      final thread = await gateway.getThread(
        atendimentoId: 7,
        limit: 20,
        offset: 40,
      );

      final enviado =
          verify(() => client.getThread(captureAny())).captured.single
              as proto.GetThreadRequest;
      expect(enviado.atendimentoId, 7);
      expect(enviado.limit, 20);
      expect(enviado.offset, 40);

      final m = thread.single;
      expect(m.id, 10);
      expect(m.geradoPorIa, isTrue);
      expect(m.resumoMidia, 'foto de um documento');
      expect(m.timestamp, DateTime(2026, 1, 1, 10));
    });

    test('resumo de mídia ausente vira null', () async {
      when(() => client.getThread(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.GetThreadResponse(
            mensagens: [
              proto.MensagemThread(
                id: 1,
                atendimentoId: 7,
                tipo: 'texto',
                conteudo: 'x',
                remetente: 'atendente',
                timestamp: _ms(DateTime(2026, 1, 1)),
                statusEnvio: 'enviado',
              ),
            ],
          ),
        ),
      );

      expect(
        (await gateway.getThread(atendimentoId: 7)).single.resumoMidia,
        isNull,
      );
    });
  });

  group('moveAtendimentoEtapa', () {
    test('envia atendimento, etapa e motivo', () async {
      when(
        () => client.moveAtendimentoEtapa(any()),
      ).thenAnswer((_) => respostaGrpc(proto.MoveAtendimentoEtapaResponse()));

      await gateway.moveAtendimentoEtapa(
        atendimentoId: 7,
        etapaDestinoId: 20,
        motivo: 'cliente pediu',
      );

      final enviado =
          verify(
                () => client.moveAtendimentoEtapa(captureAny()),
              ).captured.single
              as proto.MoveAtendimentoEtapaRequest;
      expect(enviado.atendimentoId, 7);
      expect(enviado.etapaDestinoId, 20);
      expect(enviado.motivo, 'cliente pediu');
    });

    test('falha do transporte sobe crua', () async {
      when(() => client.moveAtendimentoEtapa(any())).thenAnswer(
        (_) => falhaGrpc(proto.GrpcError.failedPrecondition('etapa invalida')),
      );

      await expectLater(
        gateway.moveAtendimentoEtapa(atendimentoId: 7, etapaDestinoId: 20),
        throwsA(isA<proto.GrpcError>()),
      );
    });
  });

  group('sendOutboundMessage', () {
    test('envia conteúdo e tipo, devolve o id persistido', () async {
      when(() => client.sendOutboundMessage(any())).thenAnswer(
        (_) => respostaGrpc(proto.SendOutboundMessageResponse(messageId: 123)),
      );

      final id = await gateway.sendOutboundMessage(
        atendimentoId: 7,
        conteudo: 'resposta do atendente',
        tipo: 'texto',
      );

      expect(id, 123);
      final enviado =
          verify(() => client.sendOutboundMessage(captureAny())).captured.single
              as proto.SendOutboundMessageRequest;
      expect(enviado.conteudo, 'resposta do atendente');
      expect(enviado.tipo, 'texto');
    });
  });

  group('streamAtendimentos', () {
    test('converte os eventos e decodifica o payload JSON', () async {
      when(() => client.streamAtendimentos(any())).thenAnswer(
        (_) => streamGrpc([
          proto.AtendimentoEvent(
            eventType: 'kanban.movido',
            tenantId: 'tenant-1',
            payload: '{"atendimento_id":7}',
          ),
        ]),
      );

      final evento = await gateway.streamAtendimentos().first;

      expect(evento.tipo, 'kanban.movido');
      expect(evento.tenantId, 'tenant-1');
      expect(evento.payload['atendimento_id'], 7);
    });

    test(
      'payload inválido degrada para mapa vazio em vez de derrubar o stream',
      () async {
        when(() => client.streamAtendimentos(any())).thenAnswer(
          (_) => streamGrpc([
            proto.AtendimentoEvent(
              eventType: 'x',
              tenantId: 't',
              payload: 'nao-e-json',
            ),
          ]),
        );

        final evento = await gateway.streamAtendimentos().first;

        expect(evento.payload, isEmpty);
      },
    );

    test('erro do stream sobe cru (a apresentação decide o backoff)', () async {
      when(() => client.streamAtendimentos(any())).thenAnswer(
        (_) => streamGrpcComFalha(
          <proto.AtendimentoEvent>[],
          proto.GrpcError.unavailable('conexao caiu'),
        ),
      );

      await expectLater(
        gateway.streamAtendimentos(),
        emitsError(isA<proto.GrpcError>()),
      );
    });
  });
}
