import 'package:meta/meta.dart';

/// Uma regra do cadastro "Transferência para atendente" (plano ia-engine-jev).
///
/// A transferência é decisão do negócio: no motor Jev, estas regras e os
/// sinais automáticos são a ÚNICA fonte de quando o bot passa a conversa para
/// uma pessoa. A condição é lida ao pé da letra — por isso a tela pede uma
/// frase exata e oferece o teste antes de ativar.
@immutable
class RegraDeTransferencia {
  final int id;
  final String nome;

  /// `condicao` (uma frase) ou `intencao` (uma intenção do catálogo).
  final String gatilhoTipo;
  final String condicao;
  final String intencaoTag;
  final List<String> exemplosSim;
  final List<String> exemplosNao;

  /// `imediato` ou `apos_coleta` (só depois de preencher [camposColeta]).
  final String momento;
  final List<String> camposColeta;

  /// `fluxo` ([destinoFluxoId]), `setor_jev` (o setor que a IA escolher) ou
  /// `padrao` (o fluxo padrão da transferência).
  final String destinoTipo;
  final int? destinoFluxoId;

  /// Ao cliente; vazio = a mensagem padrão de transferência.
  final String mensagem;

  /// `baixa`, `media` ou `alta`.
  final String sensibilidade;
  final bool ativa;

  /// Criada a partir do texto antigo (prompt, persona, comportamentos):
  /// espera revisão para valer.
  final bool sugestao;

  const RegraDeTransferencia({
    this.id = 0,
    this.nome = '',
    this.gatilhoTipo = 'condicao',
    this.condicao = '',
    this.intencaoTag = '',
    this.exemplosSim = const [],
    this.exemplosNao = const [],
    this.momento = 'imediato',
    this.camposColeta = const [],
    this.destinoTipo = 'padrao',
    this.destinoFluxoId,
    this.mensagem = '',
    this.sensibilidade = 'media',
    this.ativa = false,
    this.sugestao = false,
  });

  bool get nova => id == 0;

  RegraDeTransferencia copyWith({
    String? nome,
    String? gatilhoTipo,
    String? condicao,
    String? intencaoTag,
    List<String>? exemplosSim,
    List<String>? exemplosNao,
    String? momento,
    List<String>? camposColeta,
    String? destinoTipo,
    int? destinoFluxoId,
    bool limparDestinoFluxo = false,
    String? mensagem,
    String? sensibilidade,
  }) => RegraDeTransferencia(
    id: id,
    nome: nome ?? this.nome,
    gatilhoTipo: gatilhoTipo ?? this.gatilhoTipo,
    condicao: condicao ?? this.condicao,
    intencaoTag: intencaoTag ?? this.intencaoTag,
    exemplosSim: exemplosSim ?? this.exemplosSim,
    exemplosNao: exemplosNao ?? this.exemplosNao,
    momento: momento ?? this.momento,
    camposColeta: camposColeta ?? this.camposColeta,
    destinoTipo: destinoTipo ?? this.destinoTipo,
    destinoFluxoId: limparDestinoFluxo
        ? null
        : (destinoFluxoId ?? this.destinoFluxoId),
    mensagem: mensagem ?? this.mensagem,
    sensibilidade: sensibilidade ?? this.sensibilidade,
    ativa: ativa,
    sugestao: sugestao,
  );
}

/// Um sinal automático: liga/desliga e sensibilidade.
@immutable
class SinalAutomatico {
  final String nome;
  final bool ativo;
  final String sensibilidade;

  const SinalAutomatico({
    required this.nome,
    required this.ativo,
    this.sensibilidade = 'media',
  });

  SinalAutomatico copyWith({bool? ativo, String? sensibilidade}) =>
      SinalAutomatico(
        nome: nome,
        ativo: ativo ?? this.ativo,
        sensibilidade: sensibilidade ?? this.sensibilidade,
      );

  /// Como a tela chama cada sinal — o nome técnico é do servidor.
  String get rotulo => switch (nome) {
    'pede_humano' => 'O cliente pede uma pessoa',
    'irritacao' => 'O cliente está irritado',
    'duvida_transfere' => 'Na dúvida, transferir',
    'base_sem_resposta' => 'A base não tem a resposta',
    'resposta_sem_apoio' => 'A resposta não se apoia na base',
    _ => nome,
  };

  /// O que acontece quando o sinal está ligado ou desligado.
  String get explicacao => switch (nome) {
    'pede_humano' =>
      '"Quero falar com o Paulo", "tem alguém aí?" — transfere antes de o bot '
          'responder.',
    'irritacao' => 'Reclamação forte, ameaça de desistir ou insulto.',
    'duvida_transfere' =>
      'Quando um sinal ou uma regra fica na faixa de dúvida: ligado, transfere '
          'por precaução; desligado, o bot responde.',
    'base_sem_resposta' =>
      'Desligado, o cliente recebe a mensagem de "não encontrei"; ligado, '
          'recebe e é transferido.',
    'resposta_sem_apoio' =>
      'Desligado, a resposta sem apoio vira a mensagem de "não encontrei"; '
          'ligado, transfere.',
    _ => '',
  };

  /// Só sinais que comparam uma probabilidade têm sensibilidade.
  bool get temSensibilidade => nome == 'pede_humano' || nome == 'irritacao';
}

@immutable
class ConfiguracaoDeTransferencia {
  final List<SinalAutomatico> sinais;
  final int? fluxoPadraoId;
  final String msgTransferencia;

  /// `llm`, `sombra` ou `jev` — definido pela plataforma.
  final String motorAnalise;

  const ConfiguracaoDeTransferencia({
    this.sinais = const [],
    this.fluxoPadraoId,
    this.msgTransferencia = '',
    this.motorAnalise = 'llm',
  });
}

/// Uma transferência decidida pela IA, com o motivo — sem texto da conversa.
@immutable
class TransferenciaFeita {
  final int id;
  final int atendimentoId;
  final String motor;
  final String motivo;
  final String fluxoNome;
  final DateTime criadoEm;

  const TransferenciaFeita({
    required this.id,
    required this.atendimentoId,
    required this.motor,
    required this.motivo,
    required this.fluxoNome,
    required this.criadoEm,
  });

  /// "regra:Fechar pedido" → "Regra: Fechar pedido"; sinais pelo rótulo.
  String get motivoLegivel {
    final partes = motivo.split(':');
    final duvida = partes.first == 'duvida';
    final resto = duvida ? partes.skip(1).toList() : partes;
    final texto = switch (resto.first) {
      'regra' => 'Regra: ${resto.skip(1).join(':')}',
      'pede_humano' => 'Pediu uma pessoa',
      'irritacao' => 'Cliente irritado',
      'base_sem_resposta' => 'Base sem resposta',
      'resposta_sem_apoio' => 'Resposta sem apoio',
      'promete_o_que_nao_pode' => 'Resposta prometia o que não pode',
      '' => 'Motivo não registrado',
      final outro => outro,
    };
    return duvida ? '$texto (na dúvida)' : texto;
  }
}

@immutable
class OpcaoDeFluxo {
  final int id;
  final String nome;

  const OpcaoDeFluxo(this.id, this.nome);
}

@immutable
class OpcaoDeCampo {
  final String slug;
  final String nome;

  const OpcaoDeCampo(this.slug, this.nome);
}

/// Tudo o que a tela mostra, carregado de uma vez.
@immutable
class PainelTransferencia {
  final ConfiguracaoDeTransferencia config;
  final List<RegraDeTransferencia> regras;
  final List<TransferenciaFeita> transferencias;
  final List<OpcaoDeFluxo> fluxos;
  final List<String> intencoes;
  final List<OpcaoDeCampo> campos;

  const PainelTransferencia({
    this.config = const ConfiguracaoDeTransferencia(),
    this.regras = const [],
    this.transferencias = const [],
    this.fluxos = const [],
    this.intencoes = const [],
    this.campos = const [],
  });
}

@immutable
class ResultadoTesteRegra {
  final double probabilidade;
  final double limiar;
  final bool dispararia;
  final String modelo;

  const ResultadoTesteRegra({
    required this.probabilidade,
    required this.limiar,
    required this.dispararia,
    required this.modelo,
  });
}
