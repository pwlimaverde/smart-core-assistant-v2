import 'package:meta/meta.dart';

/// Um quadro disponível para o atendente — o fluxo, visto de quem opera.
@immutable
class FluxoDoQuadro {
  final int id;
  final String nome;
  final String departamentoNome;

  const FluxoDoQuadro({
    required this.id,
    required this.nome,
    required this.departamentoNome,
  });

  String get rotulo =>
      departamentoNome.isEmpty ? nome : '$departamentoNome · $nome';
}

/// Uma coluna do quadro.
///
/// Vem do **fluxo cadastrado**, não dos atendimentos existentes: uma coluna sem
/// conversa nenhuma precisa aparecer, senão não há para onde arrastar — e um
/// quadro recém-criado apareceria vazio, como se estivesse quebrado.
@immutable
class ColunaDoQuadro {
  final int id;
  final String nome;
  final String cor;
  final int ordem;

  /// `fila`, `trabalho`, `espera` ou `finalizacao`. Decide o status que a
  /// conversa assume ao entrar aqui.
  final String tipo;

  const ColunaDoQuadro({
    required this.id,
    required this.nome,
    required this.cor,
    required this.ordem,
    required this.tipo,
  });

  /// O status que a conversa assume ao entrar aqui.
  ///
  /// A mesma tabela que o servidor aplica. Duplicá-la aqui não é divergência:
  /// é o que permite ao cartão já mostrar o estado novo no instante do arrasto,
  /// sem uma ida extra ao servidor só para reler o que se sabe. Tipo
  /// desconhecido devolve `null` — e aí o cartão fica como está, em vez de
  /// inventar um estado.
  ///
  /// Na finalização é o **nome** que decide: um fluxo nasce com "Resolvido" e
  /// "Cancelado", ambas do mesmo tipo, e tratá-las igual faria o cartão
  /// aparecer como resolvido no instante em que alguém o cancelou.
  String? get statusResultante => switch (tipo) {
    'fila' => 'fila',
    'trabalho' => 'em_atendimento',
    'espera' => 'pendencia',
    'finalizacao' => _statusDaFinalizacao,
    _ => null,
  };

  String get _statusDaFinalizacao {
    final rotulo = nome.toLowerCase();
    if (rotulo.contains('cancel')) return 'cancelado';
    if (rotulo.contains('arquiv') || rotulo.contains('archiv')) {
      return 'arquivado';
    }
    return 'resolvido';
  }
}
