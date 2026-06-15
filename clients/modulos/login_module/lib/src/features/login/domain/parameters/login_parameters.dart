import 'package:meta/meta.dart';
import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros do login. Carrega o [AppError] tipado exibido em caso de falha.
@immutable
final class LoginParameters implements ParametersReturnResult {
  final String email;
  final String password;

  const LoginParameters({required this.email, required this.password});

  @override
  AppError get error => const ErrorAuth(message: 'Falha ao autenticar.');
}
