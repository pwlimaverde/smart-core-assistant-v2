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

  const Painel({
    required this.emAndamento,
    required this.aguardando,
    required this.mensagens24h,
    required this.conexoesAtivas,
    required this.conexoesTotal,
    required this.departamentos,
    required this.treinamentosAtivos,
  });

  /// Alguma conexão caiu — o sintoma mais grave, porque para de entrar
  /// mensagem sem ninguém perceber.
  bool get temConexaoCaida => conexoesTotal > conexoesAtivas;

  /// Sem estrutura mínima, a fila não anda: não há para onde mandar conversa.
  bool get faltaEstrutura => departamentos == 0 || conexoesTotal == 0;
}
