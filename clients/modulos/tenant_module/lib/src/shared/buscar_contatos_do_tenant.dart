import 'package:dependencies_module/dependencies_module.dart';
import 'package:operacional_module/operacional_module.dart';

import '../features/contatos/domain/errors/contatos_errors.dart';
import '../features/contatos/domain/model/contato.dart';
import '../features/contatos/domain/parameters/contatos_parameters.dart';
import '../features/contatos/domain/usecases/contatos_usecases.dart';

/// Adapta a busca de contatos do tenant ao formato que o quadro espera (C3).
///
/// Mora aqui, e não no `operacional_module`, pelo mesmo motivo do menu e dos
/// avisos: cadastro de cliente é assunto deste módulo, e a dependência entre os
/// dois corre nesta direção — é o app do tenant que compõe os dois.
///
/// A tradução para [ContatoParaAtendimento] é de propósito: o quadro precisa de
/// três campos para desenhar uma lista de escolha, e não do cadastro inteiro.
Future<List<ContatoParaAtendimento>> buscarContatosDoTenant(
  String termo,
) async {
  final resultado = await inject<ListarContatosUsecase>()(
    ListarContatosParameters(busca: termo),
  );

  return switch (resultado) {
    Success<List<Contato>, ContatosError>(:final value) => value
        .where((c) => c.ativo)
        .map(
          (c) => ContatoParaAtendimento(
            id: c.id,
            // O nome cadastrado ganha do nome de perfil; quando não há
            // nenhum dos dois, quem identifica é o telefone, e a tela o
            // mostra no lugar do nome.
            nome: c.nomeContato.isNotEmpty
                ? c.nomeContato
                : c.nomePerfilWhatsapp,
            telefone: c.telefone,
          ),
        )
        .toList(),
    // Falha vira lista vazia: quem chama trata a busca como auxiliar e não
    // derruba o diálogo por causa dela.
    _ => const <ContatoParaAtendimento>[],
  };
}
