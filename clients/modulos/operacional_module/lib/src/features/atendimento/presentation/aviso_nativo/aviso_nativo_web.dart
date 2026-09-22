/// P16 — na web o aviso é o SnackBar do quadro; aqui nada a fazer.
final class AvisoNativo {
  AvisoNativo._();

  static Future<void> iniciar({
    required void Function(int atendimentoId) aoClicar,
  }) async {}

  static Future<void> mostrar({
    required int atendimentoId,
    required String titulo,
    required String corpo,
  }) async {}
}
