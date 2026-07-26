import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros do login — só dados.
///
/// A senha atravessa as três camadas dentro deste objeto, então ele **nunca**
/// entra em log: nem diretamente, nem através dos `parameters` que o `mapError`
/// recebe como contexto. O `toString` herdado de `Object` não expõe campos, e é
/// de propósito que não há um sobrescrito aqui.
final class LoginParameters extends Parameters {
  final String email;
  final String password;

  const LoginParameters({required this.email, required this.password});
}
