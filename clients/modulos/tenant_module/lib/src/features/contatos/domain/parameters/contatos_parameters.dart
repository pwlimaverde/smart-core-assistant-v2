import 'package:return_success_or_error/return_success_or_error.dart';

final class ListarContatosParameters extends Parameters {
  /// Vazio = sem filtro. O servidor casa contra nome, telefone e nome de
  /// perfil do WhatsApp.
  final String busca;

  const ListarContatosParameters({this.busca = ''});
}

/// O que a tela manda ao cadastrar um cliente (C4).
///
/// O telefone vai como a pessoa digitou. Quem normaliza é o servidor, e é ele
/// que devolve o número final — se o cliente fizesse isso por conta, dois
/// lugares decidiriam o mesmo formato e um deles acabaria diferente do que a
/// ingestão grava.
final class CriarContatoParameters extends Parameters {
  final String telefone;
  final String nomeContato;
  final String email;

  const CriarContatoParameters({
    required this.telefone,
    this.nomeContato = '',
    this.email = '',
  });
}

/// O que a tela edita.
///
/// [telefone] vazio é "não mexe": o servidor só aceita a troca enquanto o
/// contato não tem conversa, e mandar o número atual de volta em toda edição
/// faria a recusa aparecer sem ninguém ter pedido nada.
final class AtualizarContatoParameters extends Parameters {
  final int id;
  final String nomeContato;
  final String email;
  final String telefone;

  const AtualizarContatoParameters({
    required this.id,
    this.nomeContato = '',
    this.email = '',
    this.telefone = '',
  });
}

final class DefinirContatoAtivoParameters extends Parameters {
  final int id;
  final bool ativo;

  const DefinirContatoAtivoParameters({required this.id, required this.ativo});
}
