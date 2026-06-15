// `hide AuthService`: o dependencies_module reexporta o AuthService fino do
// core_module; aqui usamos o AuthService rico do domínio do login.
import 'package:dependencies_module/dependencies_module.dart' hide AuthService;

import '../../domain/services/auth_service.dart';
import '../controllers/login_controller.dart';
import '../pages/login_page.dart';

/// Rota '/login' — registra o controller no escopo da rota e expõe a página.
final class LoginRoute extends GetItModule {
  @override
  String get path => '/login';

  @override
  Widget get page => const LoginPage();

  @override
  void binds(Injector i) {
    i.controller<LoginController>(
      () => LoginController(auth: inject<AuthService>()),
    );
  }
}
