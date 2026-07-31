import 'package:dependencies_module/dependencies_module.dart';

import '../controllers/login_controller.dart';
import '../widgets/login_form.dart';

/// Página de login. Resolve o [LoginController] do escopo da rota e exibe o
/// formulário. A navegação pós-login é do guard (reage a `authChanges`).
final class LoginPage extends StatelessWidget {
  /// Rota do cadastro de conta, quando o app oferece autocadastro.
  ///
  /// `null` no painel do superusuário, que não tem por onde alguém se
  /// cadastrar. Ver [LoginForm.rotaDeCadastro].
  final String? rotaDeCadastro;

  const LoginPage({super.key, this.rotaDeCadastro});

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      body: LoginForm(
        controller: inject<LoginController>(),
        rotaDeCadastro: rotaDeCadastro,
      ),
    );
  }
}
