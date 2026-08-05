import 'package:meta/meta.dart';

/// Um trecho de material que a IA usou para responder.
@immutable
class TrechoUsado {
  final String conteudo;

  /// Distância de cosseno: quanto **menor**, mais parecido.
  ///
  /// Aparece na tela porque é o que explica por que um trecho entrou e outro
  /// não — sem ela, "a IA respondeu errado" não tem por onde ser investigado.
  final double distancia;

  const TrechoUsado({required this.conteudo, required this.distancia});

  /// Quão parecido, em porcentagem, para quem não lida com distância de
  /// cosseno todo dia. `0` de distância é idêntico; `1`, sem relação.
  int get semelhanca => ((1 - distancia).clamp(0, 1) * 100).round();
}

/// O que a IA responderia a uma pergunta, e com base em quê.
@immutable
class Ensaio {
  final String resposta;

  /// Intenção que casou. Vazio = nenhuma dentro do limiar.
  final String comportamentoAplicado;
  final List<TrechoUsado> trechos;
  final double confiabilidade;

  /// `true` quando a IA decidiu transferir em vez de responder.
  final bool transferiria;
  final String fluxoTransferencia;

  const Ensaio({
    required this.resposta,
    required this.comportamentoAplicado,
    required this.trechos,
    required this.confiabilidade,
    required this.transferiria,
    required this.fluxoTransferencia,
  });

  /// A IA respondeu sem material nenhum e sem intenção.
  ///
  /// A resposta pode até parecer boa — o modelo inventa —, e é justamente
  /// nesse caso que quem treina precisa ser avisado: o que veio não saiu do
  /// treinamento.
  bool get semContexto => trechos.isEmpty && comportamentoAplicado.isEmpty;
}
