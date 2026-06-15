import 'package:presentation_module/presentation_module.dart';

import '../../domain/model/session.dart';
import '../../domain/services/auth_service.dart';

/// Controller da tela de login. Fala apenas com o [AuthService] (domínio).
final class LoginController extends BaseController<Session> {
  final AuthService _auth;

  LoginController({required this._auth});

  /// Dispara o login; o [BaseController.execute] mapeia loading→success/error.
  Future<void> signIn(String email, String password) =>
      execute(() => _auth.login(email: email, password: password));
}
