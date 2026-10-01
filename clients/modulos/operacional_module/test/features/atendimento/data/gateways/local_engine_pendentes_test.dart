import 'package:flutter_test/flutter_test.dart';
import 'package:operacional_module/src/features/atendimento/data/gateways/local_engine_gateway.dart';
import 'package:operacional_module/src/features/atendimento/domain/model/mensagem_thread.dart';

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

    expect(LocalEngineGateway.semAsJaEnviadas(pendentes, remotas), isEmpty);
  });

  test('a pendente que ainda não chegou ao servidor continua', () {
    final pendentes = [_msg(-1, 'custa 380', t0)];
    final remotas = [_msg(388, 'custa 380', t0, de: '558897141275')];

    expect(
      LocalEngineGateway.semAsJaEnviadas(pendentes, remotas),
      hasLength(1),
    );
  });

  test('texto repetido casa uma remota para cada pendente', () {
    final pendentes = [_msg(-2, 'ok', t0), _msg(-1, 'ok', t0)];
    final remotas = [_msg(390, 'ok', t0)];

    expect(
      LocalEngineGateway.semAsJaEnviadas(pendentes, remotas),
      hasLength(1),
    );
  });

  test('remota bem anterior à pendente não é ela', () {
    final pendentes = [_msg(-1, 'ok', t0)];
    final remotas = [_msg(300, 'ok', t0.subtract(const Duration(hours: 1)))];

    expect(
      LocalEngineGateway.semAsJaEnviadas(pendentes, remotas),
      hasLength(1),
    );
  });

  test('dead_letter aparece como falha, não como relógio', () {
    expect(
      StatusEntrega.derivar(statusEnvio: 'dead_letter'),
      StatusEntrega.falhou,
    );
  });
}
