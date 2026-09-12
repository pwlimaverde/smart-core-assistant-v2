import 'package:return_success_or_error/return_success_or_error.dart';

import '../model/campo_personalizado.dart';

/// O que a tela manda ao criar um campo.
///
/// Sem `slug`: ele é derivado do nome no servidor. É identificador — vai
/// gravado dentro de cada valor que a IA extrai — e deixá-lo à mão convidaria
/// a espaços, acentos e duplicidade.
final class CriarCampoParameters extends Parameters {
  final String nome;
  final String descricao;
  final String escopo;
  final int? fluxoId;
  final TipoCampo tipo;
  final List<OpcaoCampo> opcoes;
  final bool obrigatorio;
  final bool extrairAutomaticamente;
  final String extrairHint;
  final bool mostrarNoCard;
  final int ordem;

  const CriarCampoParameters({
    required this.nome,
    this.descricao = '',
    this.escopo = 'GLOBAL',
    this.fluxoId,
    this.tipo = TipoCampo.texto,
    this.opcoes = const [],
    this.obrigatorio = false,
    this.extrairAutomaticamente = true,
    this.extrairHint = '',
    this.mostrarNoCard = true,
    this.ordem = 0,
  });
}

/// O que a tela edita.
///
/// Sem `escopo` e `fluxoId`: mover um campo de escopo mudaria a quais
/// atendimentos ele se aplica, e os valores já coletados ficariam órfãos.
final class AtualizarCampoParameters extends Parameters {
  final int id;
  final String nome;
  final String descricao;
  final TipoCampo tipo;
  final List<OpcaoCampo> opcoes;
  final bool obrigatorio;
  final bool extrairAutomaticamente;
  final String extrairHint;
  final bool mostrarNoCard;
  final int ordem;
  final bool ativo;

  const AtualizarCampoParameters({
    required this.id,
    required this.nome,
    this.descricao = '',
    this.tipo = TipoCampo.texto,
    this.opcoes = const [],
    this.obrigatorio = false,
    this.extrairAutomaticamente = true,
    this.extrairHint = '',
    this.mostrarNoCard = true,
    this.ordem = 0,
    this.ativo = true,
  });
}

final class CampoIdParameters extends Parameters {
  final int id;
  const CampoIdParameters({required this.id});
}

/// Preenchimento manual de um campo na ficha do atendimento.
final class DefinirValorCampoParameters extends Parameters {
  final int atendimentoId;
  final int campoId;

  /// JSON na forma do tipo. `"null"` apaga de propósito — e é diferente de
  /// nunca ter sido preenchido: a IA não repreenche o que alguém apagou.
  final String valorJson;

  const DefinirValorCampoParameters({
    required this.atendimentoId,
    required this.campoId,
    required this.valorJson,
  });
}
