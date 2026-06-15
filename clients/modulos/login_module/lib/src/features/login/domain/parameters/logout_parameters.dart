import 'package:meta/meta.dart';
import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros do logout. O [refreshToken] (opcional) revoga a família inteira.
@immutable
final class LogoutParameters implements ParametersReturnResult {
  final String? refreshToken;

  const LogoutParameters({this.refreshToken});

  @override
  AppError get error => const ErrorAuth(message: 'Falha ao encerrar a sessão.');
}
