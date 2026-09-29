import 'package:meta/meta.dart';

/// Uma intenção: o que a IA deve **fazer** quando a pergunta do cliente se
/// parecer com o exemplo.
///
/// Complementa o material treinado, que diz o que ela **sabe**. Corrigir uma
/// resposta errada por aqui é imediato — não depende de reescrever e
/// reprocessar todo o material.
@immutable
class IntentIa {
  final int id;
  final String tag;
  final String grupo;

  /// Quando esta intenção se aplica. Entra no texto que vira vetor.
  final String descricao;

  /// Uma pergunta típica do cliente. Também entra no vetor.
  final String exemplo;

  /// O que a IA passa a fazer quando a intenção casa.
  final String comportamento;

  /// `false` enquanto o servidor não gerou o vetor.
  ///
  /// Até lá a intenção existe no cadastro e **não existe para a IA**: a busca
  /// semântica ignora quem não tem embedding. A tela precisa dizer isso, senão
  /// alguém cadastra e conclui que o sistema não funciona.
  final bool vetorizada;

  /// Motor Jev — os dados essenciais que o bot pede ao cliente quando esta
  /// intenção é a escolhida (tipo de entidade ou campo do cartão), em ordem.
  ///
  /// A regra "no máximo N perguntas, uma única vez" deixa de ser texto do
  /// comportamento: o servidor conta as rodadas.
  final List<String> camposColeta;

  /// Quantos dados, no máximo, numa mensagem (1 a 5).
  final int maxPerguntas;

  /// Depois da rodada (ou se o cliente já disse tudo): `transferir` ou
  /// `continuar`.
  final String aposColeta;

  const IntentIa({
    required this.id,
    required this.tag,
    required this.grupo,
    required this.descricao,
    required this.exemplo,
    required this.comportamento,
    required this.vetorizada,
    this.camposColeta = const [],
    this.maxPerguntas = 2,
    this.aposColeta = 'transferir',
  });
}
