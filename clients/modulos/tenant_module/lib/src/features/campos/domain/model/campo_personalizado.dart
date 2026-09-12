import 'package:meta/meta.dart';

/// O tipo de dado que um campo do cartão aceita.
///
/// Fechado de propósito: é o que decide como a tela desenha o controle e como
/// o servidor valida o que a IA extraiu. Um tipo livre viraria texto em todo
/// lugar, e o campo "data de retorno" aceitaria "semana que vem".
enum TipoCampo {
  texto('texto', 'Texto', 'Qualquer texto livre.'),
  numero('numero', 'Número', 'Só números — quantidades, valores, códigos.'),
  data('data', 'Data', 'Uma data no calendário.'),
  booleano('booleano', 'Sim / Não', 'Uma escolha de duas.'),
  lista('lista', 'Lista de opções', 'Escolha entre opções que você define.');

  final String valor;
  final String rotulo;
  final String explicacao;

  const TipoCampo(this.valor, this.rotulo, this.explicacao);

  static TipoCampo doValor(String v) => TipoCampo.values.firstWhere(
    (t) => t.valor == v,
    // Um tipo que o servidor conhece e a tela ainda não: mostra como texto em
    // vez de quebrar a lista inteira.
    orElse: () => TipoCampo.texto,
  );
}

/// Uma opção de um campo de lista.
///
/// O [id] é o que fica gravado no valor; o [rotulo] é o que se lê. Separados
/// porque renomear "Cartão" para "Cartão de crédito" não pode invalidar o que
/// já foi preenchido.
@immutable
class OpcaoCampo {
  final String id;
  final String rotulo;

  const OpcaoCampo({required this.id, required this.rotulo});
}

/// Um campo do cartão de atendimento, como o tenant o desenhou.
///
/// É o modelo do Trello aplicado ao atendimento: nome, tipo de dado e uma
/// descrição que serve a duas leituras — explica o campo para quem preenche à
/// mão e diz à IA o que procurar na conversa.
@immutable
class CampoPersonalizado {
  final int id;

  /// Identificador estável, derivado do nome no servidor. Aparece na tela
  /// porque é ele que vai no token do MCP e nos valores extraídos — esconder
  /// criaria dois vocabulários para a mesma coisa.
  final String slug;

  final String nome;

  /// Vale para gente e para a IA. Um campo bem descrito é um campo que a IA
  /// consegue preencher sozinha.
  final String descricao;

  /// `GLOBAL` (todo atendimento) ou `FLUXO` (só um quadro).
  final String escopo;
  final int? fluxoId;

  final TipoCampo tipo;
  final List<OpcaoCampo> opcoes;

  /// Regra de **tela**: impede concluir o atendimento sem o campo.
  final bool obrigatorio;

  /// Regra de **prompt**: a IA tenta obter no meio da conversa.
  ///
  /// Separada de [obrigatorio] de propósito. Já foram tratadas como uma só, e
  /// o efeito era marcar um campo como obrigatório e a IA sair perseguindo-o.
  final bool extrairAutomaticamente;

  /// Como perguntar sem soar interrogatório.
  final String extrairHint;

  final bool mostrarNoCard;
  final int ordem;
  final bool ativo;

  const CampoPersonalizado({
    required this.id,
    required this.slug,
    required this.nome,
    required this.descricao,
    required this.escopo,
    required this.fluxoId,
    required this.tipo,
    required this.opcoes,
    required this.obrigatorio,
    required this.extrairAutomaticamente,
    required this.extrairHint,
    required this.mostrarNoCard,
    required this.ordem,
    required this.ativo,
  });

  bool get ehGlobal => escopo != 'FLUXO';
}
