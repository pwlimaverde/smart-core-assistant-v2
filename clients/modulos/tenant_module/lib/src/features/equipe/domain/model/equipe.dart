import 'package:meta/meta.dart';

/// Um departamento — para onde a fila manda conversa.
@immutable
class Departamento {
  final int id;
  final String nome;

  /// Referência estável: não muda ao renomear, porque há registros que
  /// apontam para o departamento por ele.
  final String slug;
  final String descricao;
  final bool ativo;
  final DateTime criadoEm;

  const Departamento({
    required this.id,
    required this.nome,
    required this.slug,
    required this.descricao,
    required this.ativo,
    required this.criadoEm,
  });
}

/// Uma pessoa que atende.
@immutable
class Atendente {
  final int id;
  final String nome;
  final String email;
  final String cargo;

  /// 0 = sem departamento.
  final int departamentoId;

  /// O quadro em que trabalha. Obrigatório no banco: um atendente sem fluxo
  /// não teria coluna nenhuma para receber conversa.
  final int fluxoId;

  /// Cadastro ativo — diferente de [disponivel], que é "aceitando conversa
  /// agora". Quem saiu de férias fica ativo e indisponível.
  final bool ativo;
  final bool disponivel;
  final int maxSimultaneos;

  const Atendente({
    required this.id,
    required this.nome,
    required this.email,
    required this.cargo,
    required this.departamentoId,
    required this.fluxoId,
    required this.ativo,
    required this.disponivel,
    required this.maxSimultaneos,
  });
}

/// O que a tela de equipe mostra: as duas listas juntas, porque atendente sem
/// departamento e departamento sem atendente são os dois problemas que se
/// quer enxergar de uma vez.
@immutable
class Equipe {
  final List<Departamento> departamentos;
  final List<Atendente> atendentes;

  const Equipe({required this.departamentos, required this.atendentes});
}
