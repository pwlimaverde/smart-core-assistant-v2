import 'dart:developer' as developer;

import '../../domain/model/mensagem_thread.dart';

/// Tira das pendentes locais as que o servidor já devolveu.
///
/// O aviso de "mensagem enviada" chega pelo stream antes de o sync promover
/// a cópia local (id negativo) ao id do servidor, e a recarga daquele
/// instante trazia as duas: a mesma mensagem duas vezes na conversa. Casa
/// pelo texto do atendente enviado a partir do momento em que ela foi
/// escrita, uma remota para cada pendente.
List<MensagemThread> semAsJaEnviadas(
  List<MensagemThread> pendentes,
  List<MensagemThread> remotas,
) {
  if (pendentes.isEmpty) return pendentes;
  final livres = remotas
      .where((m) => m.id > 0 && m.remetente == 'atendente')
      .toList();
  final saida = <MensagemThread>[];
  for (final p in pendentes) {
    final i = livres.indexWhere(
      (r) =>
          r.conteudo == p.conteudo &&
          !r.timestamp.isBefore(
            p.timestamp.subtract(const Duration(seconds: 5)),
          ),
    );
    if (i < 0) {
      saida.add(p);
    } else {
      livres.removeAt(i);
    }
  }
  // P1 — só a contagem: o texto comparado é conteúdo de mensagem (PII).
  final descartadas = pendentes.length - saida.length;
  if (descartadas > 0) {
    developer.log(
      'pendentes locais já confirmadas pelo servidor',
      name: 'operacional_module.chat',
      level: 500,
      error: 'descartadas=$descartadas',
    );
  }
  return saida;
}
