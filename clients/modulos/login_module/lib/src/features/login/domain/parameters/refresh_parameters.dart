import 'package:meta/meta.dart';
import 'package:domain_models/domain_models.dart';
import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros do refresh. Carrega o refresh token persistido e o erro tipado.
@immutable
final class RefreshParameters implements ParametersReturnResult {
  final String refreshToken;

  const RefreshParameters({required this.refreshToken});

  @override
  AppError get error =>
      const ErrorUnauthorized(message: 'Sessão expirada. Entre novamente.');
}
