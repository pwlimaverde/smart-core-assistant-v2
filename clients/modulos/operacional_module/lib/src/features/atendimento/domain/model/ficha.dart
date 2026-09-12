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

/// Um campo do cartão nesta conversa: a definição mais o valor (N9 E13).
///
/// O tenant desenha os campos em "Campos do atendimento"; aqui eles aparecem
/// preenchidos — pela IA durante a conversa, ou à mão por quem atende.
@immutable
class ValorCampo {
  final int campoId;
  final String slug;
  final String nome;

  /// Explica o campo a quem preenche, e diz à IA o que procurar.
  final String descricao;

  /// `texto` | `numero` | `data` | `booleano` | `lista`.
  final String tipo;

  /// Pares `id`/`rotulo` — só em campos de lista.
  final List<({String id, String rotulo})> opcoes;

  final bool obrigatorio;

  /// Vazio = nunca preenchido. `"null"` = apagado de propósito, que é
  /// diferente: a IA não repreenche o que alguém apagou.
  final String valorJson;

  /// `MANUAL` ou `IA`. A tela mostra de onde veio — um valor que a IA deduziu
  /// merece um olhar diferente de um que a pessoa digitou.
  final String origem;

  final double confianca;

  /// Alguém escreveu ou apagou ali. A IA não passa por cima.
  final bool editadoPorHumano;

  const ValorCampo({
    required this.campoId,
    required this.slug,
    required this.nome,
    required this.descricao,
    required this.tipo,
    required this.opcoes,
    required this.obrigatorio,
    required this.valorJson,
    required this.origem,
    required this.confianca,
    required this.editadoPorHumano,
  });

  bool get preenchido => valorJson.isNotEmpty && valorJson != 'null';
  bool get veioDaIa => origem == 'IA';
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

  /// D3 — a IA responde **nesta conversa**?
  ///
  /// Assumir o atendimento desliga o bot, e por muito tempo nada devolvia o
  /// valor: uma conversa que passou por um humano ficava sem IA para sempre.
  /// O interruptor da ficha é o caminho de volta.
  ///
  /// Padrão `true`: é o padrão da coluna, e um servidor antigo que não mande o
  /// campo não deve fazer a tela anunciar um silêncio que não existe.
  final bool botPodeAtender;

  /// N9 E13 — os campos do cartão aplicáveis a esta conversa.
  ///
  /// Vazio por padrão: um servidor anterior ao E13 não manda o campo, e a
  /// ficha simplesmente não desenha a seção.
  final List<ValorCampo> campos;

  const FichaAtendimento({
    required this.catalogo,
    required this.aplicadas,
    required this.notas,
    this.botPodeAtender = true,
    this.campos = const [],
  });

  /// Reconstrói a ficha trocando só o que foi passado.
  ///
  /// Existe porque reconstruir campo a campo já custou um defeito: o
  /// `GetFichaUsecase` refazia a ficha para ordenar as notas e deixava
  /// `botPodeAtender` cair no padrão `true` — a tela anunciava a IA ligada numa
  /// conversa calada. Todo campo novo daqui em diante entra de graça.
  FichaAtendimento copyWith({
    List<Etiqueta>? catalogo,
    List<Etiqueta>? aplicadas,
    List<Nota>? notas,
    bool? botPodeAtender,
    List<ValorCampo>? campos,
  }) => FichaAtendimento(
    catalogo: catalogo ?? this.catalogo,
    aplicadas: aplicadas ?? this.aplicadas,
    notas: notas ?? this.notas,
    botPodeAtender: botPodeAtender ?? this.botPodeAtender,
    campos: campos ?? this.campos,
  );

  Set<int> get idsAplicados => aplicadas.map((e) => e.id).toSet();

  /// O que ainda dá para colar: do catálogo, o que está ativo e ainda não foi
  /// aplicado. Oferecer uma etiqueta já aplicada seria um clique sem efeito.
  List<Etiqueta> get disponiveis {
    final jaTem = idsAplicados;
    return catalogo.where((e) => e.ativo && !jaTem.contains(e.id)).toList();
  }
}
