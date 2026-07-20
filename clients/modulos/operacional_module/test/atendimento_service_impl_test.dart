import 'package:domain_models/domain_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:operacional_module/src/features/atendimento/data/services/atendimento_service_impl.dart';
import 'package:operacional_module/src/features/atendimento/domain/datasources/atendimento_data_source.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

// AtendimentoServiceImpl é a implementação de AtendimentoService que encapsula
// o AtendimentoDataSource (a fronteira externa — I/O real via gRPC/FFI) num
// try/catch, convertendo exceções em ReturnSuccessOrError. Aqui a fronteira é
// mockada com mocktail para exercitar os três ramos de cada método: sucesso,
// AppError tipado (propagado como está) e exceção genérica (mapeada para
// ErrorNetwork com a mensagem original).
class _MockAtendimentoDataSource extends Mock implements AtendimentoDataSource {}

AtendimentoResumo _resumo(int id) => AtendimentoResumo(
  id: id,
  contatoId: id,
  status: 'fila',
  assunto: 'Assunto',
  prioridade: 'normal',
  dataInicio: DateTime(2026, 1, 1),
);

MensagemThread _mensagem(int id) => MensagemThread(
  id: id,
  atendimentoId: 1,
  tipo: 'texto',
  conteudo: 'Olá',
  remetente: 'usuario',
  timestamp: DateTime(2026, 1, 1),
  statusEnvio: 'enviado',
);

void main() {
  late _MockAtendimentoDataSource datasource;
  late AtendimentoServiceImpl service;

  setUp(() {
    datasource = _MockAtendimentoDataSource();
    service = AtendimentoServiceImpl(datasource: datasource);
  });

  group('listAtendimentos', () {
    test('sucesso: devolve os itens do datasource', () async {
      when(
        () => datasource.listAtendimentos(
          status: any(named: 'status'),
          departamentoId: any(named: 'departamentoId'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => [_resumo(1)]);

      final result = await service.listAtendimentos();

      expect(result, isA<SuccessReturn<List<AtendimentoResumo>>>());
      expect((result as SuccessReturn).result, hasLength(1));
    });

    test('AppError do datasource é propagado como está', () async {
      when(
        () => datasource.listAtendimentos(
          status: any(named: 'status'),
          departamentoId: any(named: 'departamentoId'),
          limit: any(named: 'limit'),
        ),
      ).thenThrow(const ErrorUnauthorized(message: 'Acesso negado.'));

      final result = await service.listAtendimentos();

      expect(result, isA<ErrorReturn<List<AtendimentoResumo>>>());
      expect((result as ErrorReturn).result, isA<ErrorUnauthorized>());
    });

    test('exceção genérica do datasource vira ErrorNetwork com a mensagem original', () async {
      when(
        () => datasource.listAtendimentos(
          status: any(named: 'status'),
          departamentoId: any(named: 'departamentoId'),
          limit: any(named: 'limit'),
        ),
      ).thenThrow(Exception('timeout de rede'));

      final result = await service.listAtendimentos();

      expect(result, isA<ErrorReturn<List<AtendimentoResumo>>>());
      final error = (result as ErrorReturn).result;
      expect(error, isA<ErrorNetwork>());
      expect(error.message, contains('timeout de rede'));
    });
  });

  group('getThread', () {
    test('sucesso: devolve as mensagens do datasource', () async {
      when(
        () => datasource.getThread(
          atendimentoId: any(named: 'atendimentoId'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => [_mensagem(1)]);

      final result = await service.getThread(atendimentoId: 1);

      expect(result, isA<SuccessReturn<List<MensagemThread>>>());
      expect((result as SuccessReturn).result, hasLength(1));
    });

    test('AppError do datasource é propagado como está', () async {
      when(
        () => datasource.getThread(
          atendimentoId: any(named: 'atendimentoId'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenThrow(const ErrorNetwork(message: 'Servidor indisponível.'));

      final result = await service.getThread(atendimentoId: 1);

      expect(result, isA<ErrorReturn<List<MensagemThread>>>());
      expect((result as ErrorReturn).result, isA<ErrorNetwork>());
    });

    test('exceção genérica do datasource vira ErrorNetwork', () async {
      when(
        () => datasource.getThread(
          atendimentoId: any(named: 'atendimentoId'),
          limit: any(named: 'limit'),
          offset: any(named: 'offset'),
        ),
      ).thenThrow(StateError('índice corrompido'));

      final result = await service.getThread(atendimentoId: 1);

      final error = (result as ErrorReturn).result;
      expect(error, isA<ErrorNetwork>());
      expect(error.message, contains('índice corrompido'));
    });
  });

  group('moveAtendimentoEtapa', () {
    test('sucesso: devolve unit', () async {
      when(
        () => datasource.moveAtendimentoEtapa(
          atendimentoId: any(named: 'atendimentoId'),
          etapaDestinoId: any(named: 'etapaDestinoId'),
          motivo: any(named: 'motivo'),
        ),
      ).thenAnswer((_) async {});

      final result = await service.moveAtendimentoEtapa(
        atendimentoId: 1,
        etapaDestinoId: 2,
      );

      expect(result, isA<SuccessReturn<Unit>>());
    });

    test('AppError do datasource (ex.: RBAC de fluxo negado) é propagado', () async {
      when(
        () => datasource.moveAtendimentoEtapa(
          atendimentoId: any(named: 'atendimentoId'),
          etapaDestinoId: any(named: 'etapaDestinoId'),
          motivo: any(named: 'motivo'),
        ),
      ).thenThrow(const ErrorUnauthorized(message: 'Acesso negado.'));

      final result = await service.moveAtendimentoEtapa(
        atendimentoId: 1,
        etapaDestinoId: 2,
      );

      expect((result as ErrorReturn).result, isA<ErrorUnauthorized>());
    });

    test('exceção genérica do datasource vira ErrorNetwork', () async {
      when(
        () => datasource.moveAtendimentoEtapa(
          atendimentoId: any(named: 'atendimentoId'),
          etapaDestinoId: any(named: 'etapaDestinoId'),
          motivo: any(named: 'motivo'),
        ),
      ).thenThrow(Exception('falha de transporte'));

      final result = await service.moveAtendimentoEtapa(
        atendimentoId: 1,
        etapaDestinoId: 2,
      );

      final error = (result as ErrorReturn).result;
      expect(error, isA<ErrorNetwork>());
      expect(error.message, contains('falha de transporte'));
    });
  });

  group('sendOutboundMessage', () {
    test('sucesso: devolve o id da mensagem', () async {
      when(
        () => datasource.sendOutboundMessage(
          atendimentoId: any(named: 'atendimentoId'),
          conteudo: any(named: 'conteudo'),
          tipo: any(named: 'tipo'),
        ),
      ).thenAnswer((_) async => 42);

      final result = await service.sendOutboundMessage(
        atendimentoId: 1,
        conteudo: 'oi',
      );

      expect((result as SuccessReturn).result, 42);
    });

    test('AppError do datasource é propagado', () async {
      when(
        () => datasource.sendOutboundMessage(
          atendimentoId: any(named: 'atendimentoId'),
          conteudo: any(named: 'conteudo'),
          tipo: any(named: 'tipo'),
        ),
      ).thenThrow(const ErrorValidation(message: 'Conteúdo vazio.'));

      final result = await service.sendOutboundMessage(
        atendimentoId: 1,
        conteudo: '',
      );

      expect((result as ErrorReturn).result, isA<ErrorValidation>());
    });

    test('exceção genérica do datasource vira ErrorNetwork', () async {
      when(
        () => datasource.sendOutboundMessage(
          atendimentoId: any(named: 'atendimentoId'),
          conteudo: any(named: 'conteudo'),
          tipo: any(named: 'tipo'),
        ),
      ).thenThrow(Exception('conexão perdida'));

      final result = await service.sendOutboundMessage(
        atendimentoId: 1,
        conteudo: 'oi',
      );

      final error = (result as ErrorReturn).result;
      expect(error, isA<ErrorNetwork>());
      expect(error.message, contains('conexão perdida'));
    });
  });

  group('streamAtendimentos', () {
    test('repassa o stream do datasource sem transformação', () {
      final evento = AtendimentoEvento(
        tipo: 'kanban.movido',
        tenantId: 'tenant-1',
        payload: const {'atendimento_id': 1},
      );
      when(() => datasource.streamAtendimentos()).thenAnswer(
        (_) => Stream.value(evento),
      );

      expect(service.streamAtendimentos(), emits(evento));
    });
  });
}
