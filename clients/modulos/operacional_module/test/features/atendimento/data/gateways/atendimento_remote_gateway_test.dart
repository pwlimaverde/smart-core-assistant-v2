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
    registerFallbackValue(proto.AtendimentoIdRequest());
    registerFallbackValue(proto.CreateEtiquetaRequest());
    registerFallbackValue(proto.IniciarAtendimentoManualRequest());
    registerFallbackValue(proto.SetMyValorCampoRequest());
    registerFallbackValue(proto.ListarTimelineRequest());
    registerFallbackValue(proto.ListarAtendimentosDoContatoRequest());
    registerFallbackValue(proto.RemoverNotaRequest());
    registerFallbackValue(proto.UpdateEtiquetaRequest());
    registerFallbackValue(proto.DesativarEtiquetaRequest());
    registerFallbackValue(proto.AtribuirAtendimentoRequest());
    registerFallbackValue(proto.DefinirPrioridadeRequest());
    registerFallbackValue(proto.TransferirParaFluxoRequest());
    registerFallbackValue(proto.ExportarQuadroRequest());
    registerFallbackValue(proto.EnviarPresencaRequest());
    registerFallbackValue(proto.SetAtendimentoStatusRequest());
    registerFallbackValue(proto.ListMyFluxosRequest());
    registerFallbackValue(proto.MyFluxoIdRequest());
    registerFallbackValue(proto.AlternarEtiquetaRequest());
    registerFallbackValue(proto.MarcarAtendimentoLidoRequest());
    registerFallbackValue(proto.DefinirBotDaConversaRequest());
    registerFallbackValue(proto.CreateNotaRequest());
    registerFallbackValue(proto.ObterContatoDoAtendimentoRequest());
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
        busca: '5531',
        somenteMeus: true,
        somenteNaoLidos: true,
      );

      final enviado =
          verify(() => client.listAtendimentos(captureAny())).captured.single
              as proto.ListAtendimentosRequest;
      expect(enviado.status, 'em_atendimento');
      expect(enviado.departamentoId, 3);
      expect(enviado.limit, 10);
      // P1 — o recorte da v1 tem de chegar ao servidor; filtrar no cliente
      // esconderia justamente a conversa que não foi baixada.
      expect(enviado.busca, '5531');
      expect(enviado.somenteMeus, isTrue);
      expect(enviado.somenteNaoLidos, isTrue);

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

  group('contato (P13)', () {
    test('o resumo traz nome, telefone e foto do contato', () async {
      when(() => client.listAtendimentos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListAtendimentosResponse(
            atendimentos: [
              proto.AtendimentoResumo(
                id: 3,
                contatoId: 9,
                status: 'fila',
                dataInicio: _ms(DateTime(2026, 9, 1)),
                contatoNome: 'Maria',
                contatoTelefone: '5511999998888',
                contatoFotoUrl: 'https://pps.whatsapp.net/f',
              ),
            ],
          ),
        ),
      );

      final fila = await gateway.listAtendimentos();

      expect(fila.single.nomeParaExibir, 'Maria');
      expect(fila.single.contatoFotoUrl, 'https://pps.whatsapp.net/f');
    });

    test('pede o contato repassando o forcar', () async {
      when(() => client.obterContatoDoAtendimento(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ObterContatoDoAtendimentoResponse(
            contatoId: 9,
            nome: '',
            telefone: '5511999998888',
          ),
        ),
      );

      final c = await gateway.obterContatoDoAtendimento(
        atendimentoId: 3,
        forcar: true,
      );

      expect(c.nomeParaExibir, '5511999998888');
      final enviado =
          verify(
                () => client.obterContatoDoAtendimento(captureAny()),
              ).captured.single
              as proto.ObterContatoDoAtendimentoRequest;
      expect(enviado.forcar, isTrue);
    });
  });

  group('ficha e chamadas diretas ao contrato', () {
    test('getFicha mapeia etiquetas, notas e campos', () async {
      when(() => client.getDetalheAtendimento(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.DetalheAtendimentoResponse(
            catalogo: [
              proto.Etiqueta(
                id: Int64(1),
                nome: 'VIP',
                cor: '#f00',
                ativo: true,
              ),
            ],
            etiquetas: [
              proto.Etiqueta(
                id: Int64(4),
                nome: 'Segunda via',
                ativo: true,
                aplicadaPelaIa: true,
              ),
            ],
            notas: [
              proto.Nota(
                id: Int64(7),
                texto: 'ligar amanhã',
                criadoEm: _ms(DateTime(2026, 9, 1)),
              ),
            ],
            botPodeAtender: false,
            campos: [
              proto.ValorCampoDoAtendimento(
                campoId: Int64(3),
                slug: 'cpf',
                nome: 'CPF',
                tipo: 'texto',
                valorJson: '"123"',
                origem: 'ia',
                confianca: 0.9,
              ),
            ],
            dadosDoContato: [
              proto.DadoDoContato(chave: 'cidade', valor: 'Recife'),
            ],
          ),
        ),
      );

      final ficha = await gateway.getFicha(9);

      expect(ficha.catalogo.single.nome, 'VIP');
      expect(ficha.aplicadas.single.aplicadaPelaIa, isTrue);
      expect(ficha.notas.single.texto, 'ligar amanhã');
      expect(ficha.botPodeAtender, isFalse);
      expect(ficha.campos.single.slug, 'cpf');
      // P15 — os pares viram mapa na ficha.
      expect(ficha.dadosDoContato, {'cidade': 'Recife'});
    });

    test('etiquetas: criar, atualizar, alternar e desativar', () async {
      when(
        () => client.createEtiqueta(any()),
      ).thenAnswer((_) => respostaGrpc(proto.EtiquetaResponse()));
      when(() => client.updateEtiqueta(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.EtiquetaResponse(
            etiqueta: proto.Etiqueta(id: Int64(2), nome: 'Novo', ativo: true),
          ),
        ),
      );
      when(
        () => client.alternarEtiqueta(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
      when(
        () => client.desativarEtiqueta(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));

      await gateway.criarEtiqueta(nome: 'VIP', cor: '#f00');
      final atualizada = await gateway.atualizarEtiqueta(id: 2, nome: 'Novo');
      await gateway.alternarEtiqueta(
        atendimentoId: 9,
        etiquetaId: 2,
        aplicar: true,
      );
      await gateway.desativarEtiqueta(id: 2);

      expect(atualizada.nome, 'Novo');
      final alternar =
          verify(() => client.alternarEtiqueta(captureAny())).captured.single
              as proto.AlternarEtiquetaRequest;
      expect(alternar.aplicar, isTrue);
      verify(() => client.desativarEtiqueta(any())).called(1);
    });

    test('notas: criar e remover', () async {
      when(
        () => client.createNota(any()),
      ).thenAnswer((_) => respostaGrpc(proto.NotaResponse()));
      when(
        () => client.removerNota(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));

      await gateway.criarNota(atendimentoId: 9, texto: 'x');
      await gateway.removerNota(notaId: 1, atendimentoId: 9);

      verify(() => client.createNota(any())).called(1);
      verify(() => client.removerNota(any())).called(1);
    });

    test('iniciar, campo, status, bot e lido', () async {
      when(() => client.iniciarAtendimentoManual(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.IniciarAtendimentoManualResponse(
            atendimentoId: 12,
            jaExistia: true,
          ),
        ),
      );
      when(
        () => client.setMyValorCampo(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SimpleOkResponse(sucesso: true)));
      when(
        () => client.setAtendimentoStatus(any()),
      ).thenAnswer((_) => respostaGrpc(proto.SetAtendimentoStatusResponse()));
      when(
        () => client.definirBotDaConversa(any()),
      ).thenAnswer((_) => respostaGrpc(proto.DefinirBotDaConversaResponse()));
      when(() => client.marcarAtendimentoLido(any())).thenAnswer(
        (_) => respostaGrpc(proto.MarcarAtendimentoLidoResponse(marcadas: 3)),
      );

      final iniciado = await gateway.iniciarAtendimento(
        contatoId: 1,
        fluxoId: 2,
        etapaInicialId: 3,
      );
      await gateway.definirValorCampo(
        atendimentoId: 9,
        campoId: 3,
        valorJson: '"x"',
      );
      await gateway.setAtendimentoStatus(atendimentoId: 9, status: 'fechado');
      await gateway.definirBotDaConversa(atendimentoId: 9, habilitado: true);
      final lidas = await gateway.marcarAtendimentoLido(9);

      expect(iniciado.atendimentoId, 12);
      expect(iniciado.jaExistia, isTrue);
      expect(lidas, 3);
    });

    test('atribuir, prioridade, transferir, presença e exportar', () async {
      when(() => client.atribuirAtendimento(any())).thenAnswer(
        (_) => respostaGrpc(proto.AtribuirAtendimentoResponse(atribuido: true)),
      );
      when(
        () => client.definirPrioridade(any()),
      ).thenAnswer((_) => respostaGrpc(proto.DefinirPrioridadeResponse()));
      when(() => client.transferirParaFluxo(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.TransferirParaFluxoResponse(
            transferido: true,
            fluxoNome: 'Vendas',
          ),
        ),
      );
      when(() => client.enviarPresenca(any())).thenAnswer(
        (_) => respostaGrpc(proto.EnviarPresencaResponse(enviado: true)),
      );
      when(() => client.exportarQuadro(any())).thenAnswer(
        (_) => respostaGrpc(proto.ExportarQuadroResponse(csv: [65, 66])),
      );

      final atribuido = await gateway.atribuirAtendimento(atendimentoId: 9);
      await gateway.definirPrioridade(atendimentoId: 9, prioridade: 'alta');
      final fluxo = await gateway.transferirParaFluxo(
        atendimentoId: 9,
        fluxoId: 2,
      );
      final presenca = await gateway.enviarPresenca(atendimentoId: 9);
      final csv = await gateway.exportarQuadro(busca: 'ana');

      expect(atribuido, isTrue);
      expect(fluxo, 'Vendas');
      expect(presenca, isTrue);
      expect(csv, [65, 66]);
      final atribuir =
          verify(() => client.atribuirAtendimento(captureAny())).captured.single
              as proto.AtribuirAtendimentoRequest;
      // 0 no protobuf = "a mim".
      expect(atribuir.atendenteId, 0);
    });

    test('fluxos, colunas, timeline e histórico do contato', () async {
      when(() => client.listMyFluxos(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyFluxosResponse(
            fluxos: [
              proto.MyFluxo(id: 1, nome: 'Vendas', ativo: true),
              proto.MyFluxo(id: 2, nome: 'Velho', ativo: false),
            ],
          ),
        ),
      );
      when(() => client.listMyEtapasFluxo(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListMyEtapasFluxoResponse(
            etapas: [
              proto.MyEtapaFluxo(id: 5, nome: 'Novo', ordem: 1, cor: '#fff'),
            ],
          ),
        ),
      );
      when(() => client.listarTimelineAtendimento(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListarTimelineResponse(
            eventos: [
              proto.EventoDaTimeline(
                tipo: 'status',
                quando: _ms(DateTime(2026, 9, 2)),
                descricao: 'Fechado',
                automatico: true,
              ),
            ],
          ),
        ),
      );
      when(() => client.listarAtendimentosDoContato(any())).thenAnswer(
        (_) => respostaGrpc(
          proto.ListarAtendimentosDoContatoResponse(
            atendimentos: [
              proto.AtendimentoResumo(
                id: 3,
                contatoId: 9,
                status: 'fechado',
                dataInicio: _ms(DateTime(2026, 8, 1)),
              ),
            ],
          ),
        ),
      );

      final fluxos = await gateway.listFluxos();
      final colunas = await gateway.listColunas(1);
      final timeline = await gateway.listarTimeline(atendimentoId: 9);
      final historico = await gateway.listarAtendimentosDoContato(contatoId: 9);

      // Fluxo desativado não aparece no seletor do quadro.
      expect(fluxos.map((f) => f.nome), ['Vendas']);
      expect(colunas.single.nome, 'Novo');
      expect(timeline.single.automatico, isTrue);
      expect(historico.single.id, 3);
    });
  });
}
