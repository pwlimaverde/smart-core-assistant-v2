import 'update_checker.dart';

/// Na Web o app é servido pelo Caddy: cada carga da página já é a versão
/// publicada. Nada de Velopack (nem do `velopack_flutter`, que é só desktop —
/// por isso este arquivo existe e o import condicional o escolhe).
UpdateChecker criarUpdateChecker(String feedUrlPadrao) =>
    UpdateChecker(gateway: const _SemVelopack(), feedUrl: '', suportado: false);

class _SemVelopack implements VelopackGateway {
  const _SemVelopack();

  @override
  bool get instalado => false;

  @override
  Future<void> inicializar(String feedUrl) async {}

  @override
  Future<bool> haAtualizacao() async => false;

  @override
  Future<void> atualizarEReiniciar() async {}
}
