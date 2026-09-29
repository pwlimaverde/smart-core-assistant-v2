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

/// Um sinal que pesou na decisão do motor Jev: valor medido e limiar.
@immutable
class SinalDoEnsaio {
  final String nome;
  final double valor;
  final double limiar;

  const SinalDoEnsaio({
    required this.nome,
    required this.valor,
    required this.limiar,
  });

  bool get passou => valor >= limiar;

  /// Sinais que são contagem, não probabilidade: mostrar "200%" confundiria.
  bool get contagem => const {
    'coleta_faltando',
    'coleta_rodadas',
    'perguntas',
    'trechos_aprovados',
    'fora_do_horario',
  }.contains(nome);
}

/// Quanto tempo uma etapa do motor Jev levou no ensaio.
@immutable
class EtapaDoEnsaio {
  final String etapa;
  final int ms;

  const EtapaDoEnsaio({required this.etapa, required this.ms});
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

  /// Plano ia-engine-jev — `llm` ou `jev`; no motor Jev, o porquê da decisão.
  final String motor;
  final String modelo;
  final String motivoTransferencia;
  final List<SinalDoEnsaio> sinais;
  final String intencaoPrincipal;
  final double confiancaIntencao;

  /// automatica | transferida | sem_info | a_revisar | barrada | reserva
  final String decisao;

  /// Motor Jev: o ato decidido em código (transferir | responder | coletar |
  /// social | sem_info | barrada), os dados que a resposta pediu, se a
  /// redação subiu para o modelo maior e por quê, e o tempo por etapa.
  final String ato;
  final List<String> camposPerguntados;
  final bool escalada;
  final List<String> problemas;
  final String modeloLlm;
  final List<EtapaDoEnsaio> etapas;

  const Ensaio({
    required this.resposta,
    required this.comportamentoAplicado,
    required this.trechos,
    required this.confiabilidade,
    required this.transferiria,
    required this.fluxoTransferencia,
    this.motor = 'llm',
    this.modelo = '',
    this.motivoTransferencia = '',
    this.sinais = const [],
    this.intencaoPrincipal = '',
    this.confiancaIntencao = 0,
    this.decisao = '',
    this.ato = '',
    this.camposPerguntados = const [],
    this.escalada = false,
    this.problemas = const [],
    this.modeloLlm = '',
    this.etapas = const [],
  });

  /// Soma do tempo das etapas, em milissegundos.
  int get tempoTotalMs => etapas.fold(0, (soma, e) => soma + e.ms);

  bool get peloJev => motor == 'jev';

  /// A IA respondeu sem material nenhum e sem intenção.
  ///
  /// A resposta pode até parecer boa — o modelo inventa —, e é justamente
  /// nesse caso que quem treina precisa ser avisado: o que veio não saiu do
  /// treinamento.
  bool get semContexto => trechos.isEmpty && comportamentoAplicado.isEmpty;
}

/// P17 — uma avaliação do teste ainda não tratada.
///
/// `AvaliacaoPendente`, e não `AvaliacaoDeTeste`: o `dependencies_module`
/// reexporta o contrato, e o nome do tipo gerado colidiria.
class AvaliacaoPendente {
  final int id;
  final String pergunta;
  final String respostaBot;

  /// A resposta certa que a pessoa escreveu. Vazia quando ela só avaliou.
  final String respostaCorrigida;
  final bool boa;
  final DateTime criadaEm;

  const AvaliacaoPendente({
    required this.id,
    required this.pergunta,
    required this.respostaBot,
    required this.respostaCorrigida,
    required this.boa,
    required this.criadaEm,
  });

  /// Só a ruim com correção vira material: a boa não ensina nada novo, e a
  /// ruim sem correção só diz que algo está errado.
  bool get podeVirarTreinamento => !boa && respostaCorrigida.trim().isNotEmpty;

  /// O texto que vai para o treinamento: a pergunta e a resposta certa.
  String get conteudoParaTreinamento =>
      'Pergunta: $pergunta\n\nResposta: $respostaCorrigida';
}
