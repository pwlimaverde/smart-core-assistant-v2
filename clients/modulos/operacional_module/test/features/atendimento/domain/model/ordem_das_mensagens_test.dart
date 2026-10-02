import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ordem_das_mensagens.dart';

MensagemThread _msg(int id, DateTime quando, {String texto = 'oi'}) =>
    MensagemThread(
      id: id,
      atendimentoId: 5,
      tipo: 'texto',
      conteudo: texto,
      remetente: 'atendente',
      timestamp: quando,
      statusEnvio: id < 0 ? 'pendente' : 'sent',
    );

void main() {
  final t0 = DateTime(2026, 10, 1, 10);

  group('ordenarParaExibir (P1)', () {
    test('confirmadas seguem a ordem do servidor (id), não o horário', () {
      // Relógios divergentes: a de id maior tem horário menor.
      final ordem = ordenarParaExibir([
        _msg(12, t0),
        _msg(10, t0.add(const Duration(minutes: 2))),
        _msg(11, t0.add(const Duration(minutes: 1))),
      ]);

      expect(ordem.map((m) => m.id), [10, 11, 12]);
    });

    test('pendente local fica no fim mesmo com relógio atrasado', () {
      // O relógio local está atrás do servidor: por horário, a pendente
      // apareceria no meio da conversa; por id, no topo.
      final ordem = ordenarParaExibir([
        _msg(-1, t0.subtract(const Duration(hours: 1))),
        _msg(10, t0),
        _msg(11, t0.add(const Duration(minutes: 1))),
      ]);

      expect(ordem.map((m) => m.id), [10, 11, -1]);
    });

    test('pendentes ficam na ordem em que foram escritas', () {
      final ordem = ordenarParaExibir([
        _msg(-3, t0.add(const Duration(seconds: 2))),
        _msg(-1, t0),
        _msg(10, t0),
        _msg(-2, t0.add(const Duration(seconds: 1))),
      ]);

      expect(ordem.map((m) => m.id), [10, -1, -2, -3]);
    });

    test('pendentes no mesmo instante desempatam pelo id local', () {
      // O motor local atribui -1, -2, -3... : o mais negativo é o mais novo.
      final ordem = ordenarParaExibir([_msg(-2, t0), _msg(-1, t0)]);

      expect(ordem.map((m) => m.id), [-1, -2]);
    });

    test('id repetido aparece uma vez, com a última versão', () {
      final ordem = ordenarParaExibir([
        _msg(10, t0, texto: 'antiga'),
        _msg(11, t0),
        _msg(10, t0, texto: 'nova'),
      ]);

      expect(ordem.map((m) => m.id), [10, 11]);
      expect(ordem.first.conteudo, 'nova');
    });

    test('lista vazia continua vazia', () {
      expect(ordenarParaExibir(const []), isEmpty);
    });
  });
}
