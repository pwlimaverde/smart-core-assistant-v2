import 'mensagem_thread.dart';

/// P1 — a ordem em que a conversa é desenhada.
///
/// Confirmadas pela ordem do servidor (id); pendentes locais (id < 0) sempre
/// no fim, pela ordem em que foram escritas. Não ordenar tudo por horário: o
/// relógio local e o do servidor divergem, e a pendente é, por definição, a
/// mais nova. Ordenar tudo por id (o comportamento anterior) desenhava a
/// pendente no topo da conversa até o sync promovê-la, quando ela saltava
/// para baixo.
///
/// Também tira ids repetidos — a última ocorrência vence, então quem junta
/// listas põe a versão mais nova por último. A lista da tela usa o id como
/// `key` de cada bolha, e chave repetida quebra o `ListView`.
List<MensagemThread> ordenarParaExibir(Iterable<MensagemThread> todas) {
  final porId = <int, MensagemThread>{for (final m in todas) m.id: m};
  final confirmadas = porId.values.where((m) => m.id >= 0).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  // `sort` do Dart não é estável: o id desempata pendentes escritas no mesmo
  // instante. O id local é decrescente (-1, -2, ...), então o mais negativo
  // é o mais novo.
  final pendentes = porId.values.where((m) => m.id < 0).toList()
    ..sort((a, b) {
      final porHorario = a.timestamp.compareTo(b.timestamp);
      return porHorario != 0 ? porHorario : b.id.compareTo(a.id);
    });
  return [...confirmadas, ...pendentes];
}
