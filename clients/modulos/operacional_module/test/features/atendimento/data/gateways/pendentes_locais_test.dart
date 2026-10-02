import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/gateways/pendentes_locais.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/ordem_das_mensagens.dart';

MensagemThread _msg(
  int id,
  String texto,
  DateTime quando, {
  String de = 'atendente',
}) => MensagemThread(
  id: id,
  atendimentoId: 466,
  tipo: 'texto',
  conteudo: texto,
  remetente: de,
  timestamp: quando,
  statusEnvio: id < 0 ? 'pendente' : 'sent',
);

void main() {
  final t0 = DateTime(2026, 10, 1, 2, 18, 30);

  test('a pendente que o servidor já devolveu sai da conversa', () {
    final pendentes = [_msg(-1, 'custa 380', t0)];
    final remotas = [
      _msg(390, 'custa 380', t0.add(const Duration(seconds: 1))),
    ];

    expect(semAsJaEnviadas(pendentes, remotas), isEmpty);
  });

  test('a pendente que ainda não chegou ao servidor continua', () {
    final pendentes = [_msg(-1, 'custa 380', t0)];
    final remotas = [_msg(388, 'custa 380', t0, de: '558897141275')];

    expect(semAsJaEnviadas(pendentes, remotas), hasLength(1));
  });

  test('texto repetido casa uma remota para cada pendente', () {
    final pendentes = [_msg(-2, 'ok', t0), _msg(-1, 'ok', t0)];
    final remotas = [_msg(390, 'ok', t0)];

    expect(semAsJaEnviadas(pendentes, remotas), hasLength(1));
  });

  test('remota bem anterior à pendente não é ela', () {
    final pendentes = [_msg(-1, 'ok', t0)];
    final remotas = [_msg(300, 'ok', t0.subtract(const Duration(hours: 1)))];

    expect(semAsJaEnviadas(pendentes, remotas), hasLength(1));
  });

  test(
    'P1 — pendente e remota na mesma recarga: sobra só a ainda não enviada, no fim',
    () {
      // Duas enviadas em sequência; a primeira já voltou do servidor na mesma
      // página da recarga, a segunda ainda não.
      final pendentes = [
        _msg(-1, 'primeira', t0),
        _msg(-2, 'segunda', t0.add(const Duration(seconds: 1))),
      ];
      final remotas = [
        _msg(388, 'olá', t0.subtract(const Duration(minutes: 1)), de: 'bot'),
        _msg(390, 'primeira', t0.add(const Duration(seconds: 2))),
      ];

      final restantes = semAsJaEnviadas(pendentes, remotas);
      expect(restantes.map((m) => m.id), [-2]);

      // A mesma junção do gateway, na ordem da tela: a pendente que sobrou
      // fica embaixo da confirmada, sem repetir a primeira.
      final tela = ordenarParaExibir([...remotas, ...restantes]);
      expect(tela.map((m) => m.id), [388, 390, -2]);
    },
  );

  test('dead_letter aparece como falha, não como relógio', () {
    expect(
      StatusEntrega.derivar(statusEnvio: 'dead_letter'),
      StatusEntrega.falhou,
    );
  });
}
