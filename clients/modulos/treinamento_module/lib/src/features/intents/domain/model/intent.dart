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

  const IntentIa({
    required this.id,
    required this.tag,
    required this.grupo,
    required this.descricao,
    required this.exemplo,
    required this.comportamento,
    required this.vetorizada,
  });
}
