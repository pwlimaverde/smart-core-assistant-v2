import 'package:return_success_or_error/return_success_or_error.dart';

/// Parâmetros do logout.
///
/// O [refreshToken] é opcional: quando presente, o servidor revoga a **família
/// inteira** de tokens derivada dele; quando ausente (nada persistido), revoga
/// apenas a sessão do access token que vai no metadata.
final class LogoutParameters extends Parameters {
  final String? refreshToken;

  const LogoutParameters({this.refreshToken});
}
