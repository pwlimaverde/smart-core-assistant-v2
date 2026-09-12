import 'package:flutter/foundation.dart';

/// Um cliente na lista de escolha do "iniciar atendimento".
///
/// Uma forma reduzida de propósito. O cadastro de contatos é do
/// `tenant_module`, e este módulo não o conhece — a dependência corre na
/// direção contrária (é o app do tenant que injeta menu e avisos aqui).
/// Importar o `Contato` de lá inverteria isso por três campos.
@immutable
class ContatoParaAtendimento {
  final int id;
  final String nome;
  final String telefone;

  const ContatoParaAtendimento({
    required this.id,
    required this.nome,
    required this.telefone,
  });
}

/// Como o quadro procura clientes: a busca é server-side, e quem sabe
/// consultá-la é o app que monta os dois módulos.
typedef BuscarContatos =
    Future<List<ContatoParaAtendimento>> Function(String termo);
