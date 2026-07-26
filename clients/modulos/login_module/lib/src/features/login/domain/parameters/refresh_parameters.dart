import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros do refresh: o token persistido que será rotacionado.
///
/// É um segredo de longa duração (revoga a família inteira se vazar) — mesmo
/// cuidado do [LoginParameters]: fora de log, sempre.
final class RefreshParameters extends Parameters {
  final String refreshToken;

  const RefreshParameters({required this.refreshToken});
}
