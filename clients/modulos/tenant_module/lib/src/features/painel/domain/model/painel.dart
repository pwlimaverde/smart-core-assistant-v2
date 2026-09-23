import 'package:meta/meta.dart';

/// Os números da operação, num instante só.
@immutable
class Painel {
  /// Conversas com alguém cuidando.
  final int emAndamento;

  /// Na fila, esperando atendente — o número que dói quando cresce.
  final int aguardando;
  final int mensagens24h;
  final int conexoesAtivas;
  final int conexoesTotal;
  final int departamentos;
  final int treinamentosAtivos;

  /// P6 — mediana do tempo até a primeira resposta nas últimas 24h, em
  /// segundos. `-1` quando ninguém foi respondido nessa janela: é diferente de
  /// "respondido em zero segundo".
  final int primeiraRespostaMedianaS;

  const Painel({
    required this.emAndamento,
    required this.aguardando,
    required this.mensagens24h,
    required this.conexoesAtivas,
    required this.conexoesTotal,
    required this.departamentos,
    required this.treinamentosAtivos,
    this.primeiraRespostaMedianaS = -1,
  });

  /// P6 — há medida de SLA para mostrar?
  bool get temSla => primeiraRespostaMedianaS >= 0;

  /// O SLA em linguagem de quem lê: "1 min 20 s", "3 min", "2 h 5 min".
  String get slaFormatado {
    final s = primeiraRespostaMedianaS;
    if (s < 0) return '—';
    if (s < 60) return '${s}s';
    if (s < 3600) {
      final minutos = s ~/ 60;
      final resto = s % 60;
      return resto == 0 ? '${minutos}min' : '${minutos}min ${resto}s';
    }
    final horas = s ~/ 3600;
    final minutos = (s % 3600) ~/ 60;
    return minutos == 0 ? '${horas}h' : '${horas}h ${minutos}min';
  }

  /// Alguma conexão caiu — o sintoma mais grave, porque para de entrar
  /// mensagem sem ninguém perceber.
  bool get temConexaoCaida => conexoesTotal > conexoesAtivas;

  /// Sem estrutura mínima, a fila não anda: não há para onde mandar conversa.
  bool get faltaEstrutura => departamentos == 0 || conexoesTotal == 0;
}
