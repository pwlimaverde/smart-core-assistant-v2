import 'package:meta/meta.dart';

/// Um número que o sistema ignora.
///
/// A v1 chamava a lista de "whitelist", e o nome mentia: ela não libera
/// ninguém — ela IGNORA. Número que está nela não abre atendimento, não aciona a
/// IA e não recebe pesquisa de satisfação. Serve para o número da própria
/// equipe, o do contador, o do fornecedor que só manda boleto — conversas que
/// não são atendimento e que sujavam o quadro.
@immutable
class NumeroIgnorado {
  final int id;
  final String nome;
  final String telefone;

  /// Desligado continua na lista, mas volta a ser atendido. É como se desfaz a
  /// regra sem perder o registro de que ela existiu.
  final bool ativo;

  final DateTime criadoEm;

  const NumeroIgnorado({
    required this.id,
    required this.nome,
    required this.telefone,
    required this.ativo,
    required this.criadoEm,
  });
}
