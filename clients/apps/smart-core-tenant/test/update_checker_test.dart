import 'package:flutter_test/flutter_test.dart';
import 'package:smart_core_tenant/platform/update_checker.dart';

/// Velopack de mentira: o feed "tem" ou "não tem" versão nova, e cada etapa
/// pode falhar. A instalação real (Setup → feed → update) é provada no CI
/// Windows, no job `auto-update-e2e` do release-windows.yml.
class _VelopackFalso implements VelopackGateway {
  _VelopackFalso({
    this.instalado = true,
    this.feedTemVersaoNova = false,
    this.falhaAoIniciar = false,
    this.falhaNoFeed = false,
  });

  @override
  final bool instalado;
  final bool feedTemVersaoNova;
  final bool falhaAoIniciar;
  final bool falhaNoFeed;

  final chamadas = <String>[];

  @override
  Future<void> inicializar(String feedUrl) async {
    chamadas.add('inicializar $feedUrl');
    if (falhaAoIniciar) throw Exception('dll ausente');
  }

  @override
  Future<bool> haAtualizacao() async {
    chamadas.add('haAtualizacao');
    if (falhaNoFeed) throw Exception('HTTP 502');
    return feedTemVersaoNova;
  }

  @override
  Future<void> atualizarEReiniciar() async => chamadas.add('atualizar');
}

const _feed = 'https://releases.smartcoreassistant.com.br/feed/beta';

void main() {
  group('UpdateChecker', () {
    test(
      'versão nova no feed: baixa, aplica e reinicia sem perguntar',
      () async {
        final velopack = _VelopackFalso(feedTemVersaoNova: true);
        final checker = UpdateChecker(
          gateway: velopack,
          feedUrl: _feed,
          suportado: true,
        );

        expect(await checker.verificar(), ResultadoAtualizacao.atualizando);
        expect(velopack.chamadas, [
          'inicializar $_feed',
          'haAtualizacao',
          'atualizar',
        ]);
      },
    );

    test('feed sem versão nova: não atualiza', () async {
      final velopack = _VelopackFalso();
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: _feed,
        suportado: true,
      );

      expect(await checker.verificar(), ResultadoAtualizacao.emDia);
      expect(velopack.chamadas, isNot(contains('atualizar')));
    });

    test('Web (sem suporte): não toca no Velopack', () async {
      final velopack = _VelopackFalso(feedTemVersaoNova: true);
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: _feed,
        suportado: false,
      );

      expect(await checker.verificar(), ResultadoAtualizacao.ignorado);
      expect(velopack.chamadas, isEmpty);
    });

    test('feed vazio desliga a checagem', () async {
      final velopack = _VelopackFalso(feedTemVersaoNova: true);
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: '',
        suportado: true,
      );

      expect(await checker.verificar(), ResultadoAtualizacao.ignorado);
      expect(velopack.chamadas, isEmpty);
    });

    test('fora da instalação do Velopack: nem carrega a biblioteca', () async {
      final velopack = _VelopackFalso(
        instalado: false,
        feedTemVersaoNova: true,
      );
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: _feed,
        suportado: true,
      );

      expect(await checker.verificar(), ResultadoAtualizacao.naoInstalado);
      expect(velopack.chamadas, isEmpty);
    });

    test('falha ao iniciar não derruba o app e não consulta o feed', () async {
      final velopack = _VelopackFalso(
        falhaAoIniciar: true,
        feedTemVersaoNova: true,
      );
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: _feed,
        suportado: true,
      );

      expect(await checker.verificar(), ResultadoAtualizacao.falhou);
      expect(velopack.chamadas, ['inicializar $_feed']);
    });

    test('feed fora do ar vira falha registrada, sem exceção', () async {
      final velopack = _VelopackFalso(falhaNoFeed: true);
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: _feed,
        suportado: true,
      );

      expect(await checker.verificar(), ResultadoAtualizacao.falhou);
    });

    test('preparar inicializa uma vez só', () async {
      final velopack = _VelopackFalso();
      final checker = UpdateChecker(
        gateway: velopack,
        feedUrl: _feed,
        suportado: true,
      );

      expect(await checker.preparar(), isNull);
      await checker.verificar();
      expect(
        velopack.chamadas.where((c) => c.startsWith('inicializar')),
        hasLength(1),
      );
    });
  });
}
