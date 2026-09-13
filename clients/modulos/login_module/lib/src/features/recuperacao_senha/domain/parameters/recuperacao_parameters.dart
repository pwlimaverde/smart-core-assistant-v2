import 'package:return_success_or_error/return_success_or_error.dart';

/// Pedido do link de redefinição (N11 E8).
///
/// `login` aceita e-mail ou nome de usuário, como a própria tela de login: quem
/// esqueceu a senha não deveria ter de lembrar com qual dos dois se cadastrou.
final class SolicitarRedefinicaoParameters extends Parameters {
  final String login;

  const SolicitarRedefinicaoParameters({required this.login});
}

/// Troca da senha com o token que veio no link.
///
/// Carrega a senha nova: como o `LoginParameters`, nunca entra em log — nem pelo
/// `parameters` do `mapError`.
final class RedefinirSenhaParameters extends Parameters {
  final String token;
  final String novaSenha;

  const RedefinirSenhaParameters({
    required this.token,
    required this.novaSenha,
  });
}
