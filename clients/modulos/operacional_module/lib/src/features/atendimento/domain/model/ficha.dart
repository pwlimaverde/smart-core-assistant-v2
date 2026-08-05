import 'package:meta/meta.dart';

/// Uma etiqueta do catálogo do tenant.
@immutable
class Etiqueta {
  final int id;
  final String nome;
  final String cor;
  final String descricao;

  /// Do **catálogo**. Uma etiqueta desativada continua aparecendo nas conversas
  /// em que já estava — sumir com ela reescreveria o passado —, mas não é mais
  /// oferecida para colar em conversa nova.
  final bool ativo;

  const Etiqueta({
    required this.id,
    required this.nome,
    required this.cor,
    required this.descricao,
    required this.ativo,
  });
}

/// Anotação interna sobre o atendimento. O contato nunca a vê.
@immutable
class Nota {
  final int id;
  final String texto;
  final DateTime criadoEm;

  const Nota({required this.id, required this.texto, required this.criadoEm});
}

/// A ficha de um atendimento: o que se sabe sobre a conversa além das
/// mensagens.
@immutable
class FichaAtendimento {
  /// Todas as etiquetas que o tenant tem para escolher.
  final List<Etiqueta> catalogo;

  /// As que estão coladas nesta conversa.
  final List<Etiqueta> aplicadas;
  final List<Nota> notas;

  const FichaAtendimento({
    required this.catalogo,
    required this.aplicadas,
    required this.notas,
  });

  Set<int> get idsAplicados => aplicadas.map((e) => e.id).toSet();

  /// O que ainda dá para colar: do catálogo, o que está ativo e ainda não foi
  /// aplicado. Oferecer uma etiqueta já aplicada seria um clique sem efeito.
  List<Etiqueta> get disponiveis {
    final jaTem = idsAplicados;
    return catalogo.where((e) => e.ativo && !jaTem.contains(e.id)).toList();
  }
}
