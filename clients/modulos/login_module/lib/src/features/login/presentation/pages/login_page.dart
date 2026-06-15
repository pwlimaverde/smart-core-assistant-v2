import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/login_controller.dart';
import '../widgets/login_form.dart';

/// Página de login. Resolve o [LoginController] do escopo da rota e exibe o
/// formulário. A navegação pós-login é do guard (reage a `authChanges`).
final class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: LoginForm(controller: inject<LoginController>()),
      ),
    );
  }
}
