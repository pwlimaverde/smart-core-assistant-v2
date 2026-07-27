import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/errors/atendimento_errors.dart';
import 'package:operacional_module/src/features/atendimento/domain/gateways/atendimento_gateway.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_evento.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/atendimento_resumo.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/list_atendimentos_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/move_atendimento_etapa_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/parameters/send_outbound_message_parameters.dart';
import 'package:operacional_module/src/features/atendimento/domain/usecases/atendimento_usecases.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

import '../support/fake_gateway.dart';

/// Repositório fora do contrato — exercita o `onUnexpected` das bases.
final class _RepoQueLanca<TData, TParams extends Parameters, TError>
    implements Repository<TData, TParams, TError> {
  @override
  Future<ReturnSuccessOrError<TData, TError>> call(TParams parameters) async {
    throw StateError('repositorio fora do contrato');
  }
}

void main() {
  group('onUnexpected das operações restantes', () {
    test('listAtendimentos converte bug do repositório', () async {
      final r = await ListAtendimentosUsecase(
        repository:
            _RepoQueLanca<
              List<AtendimentoResumo>,
              ListAtendimentosParameters,
              ListAtendimentosError
            >(),
      )(const ListAtendimentosParameters());

      expect((r as Failure).error, isA<ListAtendimentosInesperado>());
    });

    test('moveAtendimentoEtapa converte bug do repositório', () async {
      final r =
          await MoveAtendimentoEtapaUsecase(
            repository:
                _RepoQueLanca<
                  Unit,
                  MoveAtendimentoEtapaParameters,
                  MoveAtendimentoEtapaError
                >(),
          )(
            const MoveAtendimentoEtapaParameters(
              atendimentoId: 1,
              etapaDestinoId: 2,
            ),
          );

      expect((r as Failure).error, isA<MoveEtapaInesperado>());
    });

    test('sendOutboundMessage converte bug do repositório', () async {
      final r = await SendOutboundMessageUsecase(
        repository:
            _RepoQueLanca<
              int,
              SendOutboundMessageParameters,
              SendOutboundMessageError
            >(),
      )(const SendOutboundMessageParameters(atendimentoId: 1, conteudo: 'oi'));

      expect((r as Failure).error, isA<SendMessageInesperado>());
    });
  });

  group('LocalEngineFalha', () {
    test('preserva a causa e descreve a origem no toString', () async {
      const causa = 'database is locked';
      const falha = LocalEngineFalha('falha no motor local: $causa', causa);

      expect(falha.causa, causa);
      expect(falha.toString(), contains('LocalEngineFalha'));
      expect(falha.message, contains('motor local'));
    });
  });

  group('modelos de domínio', () {
    test('AtendimentoResumo.copyWith troca etapa e status', () {
      final original = atendimentoDeTeste(id: 1, etapaAtualId: 10);

      final movido = original.copyWith(etapaAtualId: 20, status: 'concluido');

      expect(movido.id, 1, reason: 'a identidade não muda');
      expect(movido.etapaAtualId, 20);
      expect(movido.status, 'concluido');
      expect(original.etapaAtualId, 10, reason: 'o original é imutável');
    });

    test('AtendimentoResumo.copyWith sem argumentos preserva tudo', () {
      final original = atendimentoDeTeste(id: 3, etapaAtualId: 5);

      final copia = original.copyWith();

      expect(copia.etapaAtualId, 5);
      expect(copia.status, original.status);
      expect(copia.assunto, original.assunto);
    });

    test('AtendimentoEvento expõe o atendimento do payload', () {
      const evento = AtendimentoEvento(
        tipo: 'kanban.movido',
        tenantId: 't1',
        payload: {'atendimento_id': 42},
      );

      expect(evento.atendimentoId, 42);
    });

    test('AtendimentoEvento sem atendimento no payload devolve null', () {
      // O stream carrega eventos de tipos variados; nem todos referenciam um
      // atendimento, e o controller usa esse null para decidir se recarrega.
      const evento = AtendimentoEvento(
        tipo: 'tenant.atualizado',
        tenantId: 't1',
        payload: {},
      );

      expect(evento.atendimentoId, isNull);
    });

    test('MensagemThread guarda o resumo de mídia quando existe', () {
      final comMidia = MensagemThread(
        id: 1,
        atendimentoId: 1,
        tipo: 'imagem',
        conteudo: 'url',
        remetente: 'cliente',
        timestamp: DateTime(2026, 1, 1),
        statusEnvio: 'entregue',
        geradoPorIa: false,
        resumoMidia: 'foto de um documento',
      );

      expect(comMidia.resumoMidia, 'foto de um documento');
      expect(comMidia.geradoPorIa, isFalse);
    });
  });
}
